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
  }

  Future<void> selectSession(SleepSession session) async {
    state = state.copyWith(isLoading: true, selectedSession: session);
    final epochs = await _database.getSleepEpochs(session.id);
    state = state.copyWith(selectedEpochs: epochs, isLoading: false);
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
}

final sleepHistoryProvider =
    StateNotifierProvider<SleepHistoryController, SleepHistoryState>((ref) {
  final engine = ref.watch(sleepEngineProvider);
  return SleepHistoryController(engine, ref);
});
