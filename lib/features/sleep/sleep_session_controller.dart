import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ble/polar_ble_manager.dart';
import '../../core/database/health_database.dart';
import '../../core/database/models/sleep_record.dart';
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

class SleepHistoryState {
  final List<SleepSession> sessions;
  final SleepSession? selectedSession;
  final List<SleepEpoch> selectedEpochs;
  final bool isLoading;

  SleepHistoryState({
    required this.sessions,
    this.selectedSession,
    this.selectedEpochs = const [],
    this.isLoading = false,
  });

  SleepHistoryState copyWith({
    List<SleepSession>? sessions,
    SleepSession? selectedSession,
    List<SleepEpoch>? selectedEpochs,
    bool? isLoading,
  }) {
    return SleepHistoryState(
      sessions: sessions ?? this.sessions,
      selectedSession: selectedSession ?? this.selectedSession,
      selectedEpochs: selectedEpochs ?? this.selectedEpochs,
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
      SleepSession? selected = state.selectedSession;
      List<SleepEpoch> epochs = state.selectedEpochs;

      if (sessions.isNotEmpty) {
        selected = sessions.first;
        epochs = await _database.getSleepEpochs(selected.id);
      }

      state = state.copyWith(
        sessions: sessions,
        selectedSession: selected,
        selectedEpochs: epochs,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
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
  /// downloads recorded samples, runs on-device sleep staging, and persists the session.
  Future<SleepSession?> syncOfflineSleep({Function(String status)? onProgress}) async {
    final bleManager = _ref.read(polarBleManagerProvider);

    try {
      state = state.copyWith(isLoading: true);
      onProgress?.call('正在准备传输通道与检查手环状态...');

      return await bleManager.withFileTransferSession(() async {
        onProgress?.call('正在读取手环内置存储列表...');
        final entries = await bleManager.listOfflineRecordings();

        if (entries.isEmpty) {
          debugPrint('[SleepSync] No offline recordings found on device');
          state = state.copyWith(isLoading: false);
          return null;
        }

        // Sort by date descending (newest first)
        entries.sort((a, b) => b.date.compareTo(a.date));
        debugPrint('[SleepSync] Total entries found on sensor: ${entries.length}');

        // Retrieve existing sessions to skip already imported sessions
        final existingSessions = await _database.getSleepSessions(limit: 60);

        bool isAlreadyImported(DateTime entryDate) {
          return existingSessions.any((s) =>
              s.startTime.difference(entryDate).inMinutes.abs() < 15);
        }

        final unSyncedEntries = entries.where((e) => !isAlreadyImported(e.date)).toList();
        debugPrint('[SleepSync] Unsynced entries to import: ${unSyncedEntries.length}');

        if (unSyncedEntries.isEmpty) {
          onProgress?.call('手环内所有记录此前已同步完毕');
          await loadSessions();
          state = state.copyWith(isLoading: false);
          // Select and return the latest existing session if available
          if (existingSessions.isNotEmpty) {
            await selectSession(existingSessions.first);
            return existingSessions.first;
          }
          return null;
        }

        SleepSession? latestProcessedSession;
        int processedCount = 0;

        for (int i = 0; i < unSyncedEntries.length; i++) {
          final entry = unSyncedEntries[i];
          onProgress?.call('正在下载睡眠数据 (${i + 1}/${unSyncedEntries.length})...');

          final exerciseData = await bleManager.fetchOfflineRecording(entry);
          if (exerciseData == null || exerciseData.samples.isEmpty) {
            debugPrint('[SleepSync] Skipping empty exercise: ${entry.entryId}');
            continue;
          }

          // At least 30 samples (30 seconds)
          if (exerciseData.samples.length >= 30) {
            onProgress?.call('正在本地分析 30 秒分期与 HRV (${i + 1}/${unSyncedEntries.length})...');
            final session = await _sleepEngine.processOfflineExercise(
              startTime: entry.date,
              exerciseData: exerciseData,
              customSessionId: entry.entryId.isNotEmpty ? 'sense_${entry.entryId}' : null,
            );

            if (session != null) {
              processedCount++;
              if (latestProcessedSession == null || session.startTime.isAfter(latestProcessedSession.startTime)) {
                latestProcessedSession = session;
              }
            }
          } else {
            debugPrint('[SleepSync] Skipping short exercise (<30 samples): ${entry.entryId}');
          }
        }

        await loadSessions();

        if (latestProcessedSession != null) {
          await selectSession(latestProcessedSession);
        } else if (existingSessions.isNotEmpty) {
          await selectSession(existingSessions.first);
        }

        state = state.copyWith(isLoading: false);
        return latestProcessedSession ?? (existingSessions.isNotEmpty ? existingSessions.first : null);
      });
    } catch (e) {
      debugPrint('[SleepSync] Sync offline sleep exception: $e');
      state = state.copyWith(isLoading: false);
      return null;
    }
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
