import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      onProgress?.call('Reading recordings from Sense memory...');

      final entries = await bleManager.listOfflineRecordings();
      if (entries.isEmpty) {
        state = state.copyWith(isLoading: false);
        return null;
      }

      // Sort by date descending to get the most recent overnight recording
      entries.sort((a, b) => b.date.compareTo(a.date));
      final latestEntry = entries.first;

      onProgress?.call('Downloading recorded samples...');
      final exerciseData = await bleManager.fetchOfflineRecording(latestEntry);

      if (exerciseData == null || exerciseData.samples.isEmpty) {
        state = state.copyWith(isLoading: false);
        return null;
      }

      onProgress?.call('Analyzing 30-second epochs & HRV...');
      final session = await _sleepEngine.processOfflineExercise(
        startTime: latestEntry.date,
        exerciseData: exerciseData,
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

  /// Generates a complete 7.5-hour mock offline sleep session for instant testing & hypnogram inspection
  Future<SleepSession?> generateMockOfflineSleep() async {
    final bleManager = _ref.read(polarBleManagerProvider);
    state = state.copyWith(isLoading: true);

    try {
      final mockData = bleManager.generateMockSleepExerciseData();
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
