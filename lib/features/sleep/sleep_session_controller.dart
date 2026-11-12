import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ble/polar_ble_manager.dart';
import '../../core/database/health_database.dart';
import '../../core/database/models/sleep_record.dart';
import '../../core/localization/app_strings.dart';
import '../sedentary/sedentary_notifier.dart';
import 'sleep_engine.dart';

final sleepEngineProvider = Provider<SleepEngine>((ref) {
  final engine = SleepEngine();
  ref.onDispose(() => engine.dispose());
  return engine;
});

final liveSleepStatusProvider = StreamProvider<LiveSleepStatus>((ref) {
  final engine = ref.watch(sleepEngineProvider);
  return engine.statusStream;
});

class OfflineSyncResult {
  final SleepSession? session;
  final int entriesFound;
  final int syncedCount;
  final int skippedAlreadySynced;
  final int skippedTooShort;
  final String? errorMessage;
  final Map<String, dynamic>? diagnostics;

  const OfflineSyncResult({
    this.session,
    this.entriesFound = 0,
    this.syncedCount = 0,
    this.skippedAlreadySynced = 0,
    this.skippedTooShort = 0,
    this.errorMessage,
    this.diagnostics,
  });

  bool get isSuccess => session != null;
}

class SleepHistoryState {
  final List<SleepSession> sessions;
  final SleepSession? selectedSession;
  final List<SleepEpoch> selectedEpochs;
  final double baseline14DayRmssd;
  final bool isLoading;

  SleepHistoryState({
    required this.sessions,
    this.selectedSession,
    this.selectedEpochs = const [],
    this.baseline14DayRmssd = 42.0,
    this.isLoading = false,
  });

  SleepHistoryState copyWith({
    List<SleepSession>? sessions,
    SleepSession? selectedSession,
    List<SleepEpoch>? selectedEpochs,
    double? baseline14DayRmssd,
    bool? isLoading,
  }) {
    return SleepHistoryState(
      sessions: sessions ?? this.sessions,
      selectedSession: selectedSession ?? this.selectedSession,
      selectedEpochs: selectedEpochs ?? this.selectedEpochs,
      baseline14DayRmssd: baseline14DayRmssd ?? this.baseline14DayRmssd,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class SleepHistoryController extends StateNotifier<SleepHistoryState> {
  final HealthDatabase _database = HealthDatabase();
  final SleepEngine _sleepEngine;
  final Ref _ref;

  SleepHistoryController(this._sleepEngine, this._ref)
      : super(SleepHistoryState(sessions: [], isLoading: true)) {
    loadSessions();
  }

  Future<void> loadSessions() async {
    try {
      state = state.copyWith(isLoading: true);
      final sessions = await _database.getSleepSessions(limit: 30);
      final baselineRmssd = await _database.get14DayBaselineRmssd();
      SleepSession? selected;
      List<SleepEpoch> epochs = [];

      if (sessions.isNotEmpty) {
        final previousSelectedId = state.selectedSession?.id;
        selected = sessions.firstWhere(
          (s) => s.id == previousSelectedId,
          orElse: () => sessions.first,
        );
        epochs = await _database.getSleepEpochs(selected.id);
      }

      state = SleepHistoryState(
        sessions: sessions,
        selectedSession: selected,
        selectedEpochs: epochs,
        baseline14DayRmssd: baselineRmssd,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> deleteSession(String sessionId) async {
    await _database.deleteSleepSession(sessionId);
    await loadSessions();
  }

  Future<void> selectSession(SleepSession session) async {
    try {
      state = state.copyWith(isLoading: true, selectedSession: session);
      final epochs = await _database.getSleepEpochs(session.id);
      state = state.copyWith(selectedEpochs: epochs, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> startTracking() async {
    final bleManager = _ref.read(polarBleManagerProvider);
    await _sleepEngine.startSession(
      accStream: bleManager.accStream,
      ppiStream: bleManager.ppiStream,
    );
  }

  Future<void> stopTracking() async {
    final session = await _sleepEngine.stopSession();
    if (session != null) {
      await loadSessions();
    }
  }

  /// Synchronizes offline sleep recordings from Polar Verity Sense internal memory,
  /// returning detailed counts and diagnostic info alongside any imported session.
  Future<OfflineSyncResult> syncOfflineSleepDetailed({
    Function(String status)? onProgress,
    AppStrings? strings,
  }) async {
    final bleManager = _ref.read(polarBleManagerProvider);
    final AppStrings s = strings ?? _ref.read<AppStrings>(stringsProvider);

    try {
      state = state.copyWith(isLoading: true);
      onProgress?.call(s.syncProgressPreparing);

      return await bleManager.withFileTransferSession(() async {
        onProgress?.call(s.syncProgressListing);
        final entries = await bleManager.listOfflineRecordings();

        if (entries.isEmpty) {
          debugPrint(
            '[SleepSync] No offline recordings found. error=${bleManager.lastSyncError}, diag=${bleManager.lastStorageDiagnostics}',
          );
          state = state.copyWith(isLoading: false);
          return OfflineSyncResult(
            entriesFound: 0,
            errorMessage: bleManager.lastSyncError,
            diagnostics: bleManager.lastStorageDiagnostics,
          );
        }

        // Sort by date descending (newest first)
        entries.sort((a, b) => b.date.compareTo(a.date));
        debugPrint('[SleepSync] Total entries found on sensor: ${entries.length}');

        // Retrieve existing sessions to skip already imported sessions
        final existingSessions = await _database.getSleepSessions(limit: 60);

        bool isAlreadyImported(String entryId, DateTime entryDate) {
          final targetId = entryId.isNotEmpty ? 'sense_$entryId' : null;
          return existingSessions.any((s) =>
              (targetId != null && s.id == targetId) ||
              s.startTime.difference(entryDate).inMinutes.abs() < 10);
        }

        final unSyncedEntries =
            entries.where((e) => !isAlreadyImported(e.entryId, e.date)).toList();
        final skippedAlready = entries.length - unSyncedEntries.length;
        debugPrint(
          '[SleepSync] Unsynced entries to import: ${unSyncedEntries.length}, skippedAlready: $skippedAlready',
        );

        if (unSyncedEntries.isEmpty) {
          onProgress?.call(s.syncProgressAlreadyDone);
          await loadSessions();
          state = state.copyWith(isLoading: false);
          if (existingSessions.isNotEmpty) {
            await selectSession(existingSessions.first);
            return OfflineSyncResult(
              session: existingSessions.first,
              entriesFound: entries.length,
              syncedCount: 0,
              skippedAlreadySynced: skippedAlready,
            );
          }
          return OfflineSyncResult(
            entriesFound: entries.length,
            skippedAlreadySynced: skippedAlready,
          );
        }

        SleepSession? latestProcessedSession;
        int processedCount = 0;
        int skippedTooShort = 0;
        String? fetchError;

        for (int i = 0; i < unSyncedEntries.length; i++) {
          final entry = unSyncedEntries[i];
          onProgress?.call(s.syncProgressDownloading(i + 1, unSyncedEntries.length));

          final exerciseData = await bleManager.fetchOfflineRecording(entry);
          if (exerciseData == null) {
            fetchError ??= bleManager.lastSyncError;
            debugPrint('[SleepSync] Fetch failed for exercise: ${entry.entryId}');
            continue;
          }
          if (exerciseData.samples.isEmpty) {
            skippedTooShort++;
            debugPrint('[SleepSync] Skipping empty exercise: ${entry.entryId}');
            continue;
          }

          // At least 30 samples (30 seconds)
          if (exerciseData.samples.length >= 30) {
            onProgress?.call(s.syncProgressAnalyzing(i + 1, unSyncedEntries.length));
            final session = await _sleepEngine.processOfflineExercise(
              startTime: entry.date,
              exerciseData: exerciseData,
              customSessionId: entry.entryId.isNotEmpty ? 'sense_${entry.entryId}' : null,
            );

            if (session != null) {
              processedCount++;
              if (latestProcessedSession == null ||
                  session.startTime.isAfter(latestProcessedSession.startTime)) {
                latestProcessedSession = session;
              }
            }
          } else {
            skippedTooShort++;
            debugPrint(
              '[SleepSync] Skipping short exercise (${exerciseData.samples.length} samples < 30): ${entry.entryId}',
            );
          }
        }

        await loadSessions();

        if (latestProcessedSession != null) {
          await selectSession(latestProcessedSession);
        }

        state = state.copyWith(isLoading: false);
        return OfflineSyncResult(
          session: latestProcessedSession,
          entriesFound: entries.length,
          syncedCount: processedCount,
          skippedAlreadySynced: skippedAlready,
          skippedTooShort: skippedTooShort,
          errorMessage: latestProcessedSession == null ? (fetchError ?? bleManager.lastSyncError) : null,
          diagnostics: latestProcessedSession == null ? bleManager.lastStorageDiagnostics : null,
        );
      });
    } catch (e) {
      debugPrint('[SleepSync] Sync offline sleep exception: $e');
      state = state.copyWith(isLoading: false);
      return OfflineSyncResult(
        errorMessage: e.toString(),
        diagnostics: bleManager.lastStorageDiagnostics,
      );
    }
  }

  /// Convenience wrapper returning only the imported/selected [SleepSession].
  Future<SleepSession?> syncOfflineSleep({Function(String status)? onProgress}) async {
    final result = await syncOfflineSleepDetailed(onProgress: onProgress);
    return result.session;
  }

  /// Generates a complete 7.5-hour mock offline sleep session for instant testing & hypnogram inspection
  Future<SleepSession?> generateMockOfflineSleep() async {
    state = state.copyWith(isLoading: true);

    try {
      final mockData = PolarBleManager.generateMockSleepExerciseData();
      final startTime = DateTime.now().subtract(const Duration(hours: 7, minutes: 45));
      final session = await _sleepEngine.processOfflineExercise(
        startTime: startTime,
        exerciseData: mockData,
      );

      await loadSessions();

      if (session != null) {
        await selectSession(session);
      }

      return session;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return null;
    }
  }
}

final sleepHistoryProvider =
    StateNotifierProvider<SleepHistoryController, SleepHistoryState>((ref) {
  final engine = ref.watch(sleepEngineProvider);
  return SleepHistoryController(engine, ref);
});
