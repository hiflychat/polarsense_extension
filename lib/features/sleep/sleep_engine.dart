import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:polar/polar.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/health_database.dart';
import '../../core/database/models/sleep_record.dart';
import '../../core/notifications/notification_service.dart';
import '../sedentary/sedentary_engine.dart';
import 'hrv_calculator.dart';
import 'sleep_staging_model.dart';
import 'recovery_score_calculator.dart';

class LiveSleepStatus {
  final bool isTracking;
  final String? sessionId;
  final Duration elapsed;
  final double currentHr;
  final double currentRmssd;
  final SleepStage currentStage;
  final int totalEpochs;

  LiveSleepStatus({
    required this.isTracking,
    this.sessionId,
    required this.elapsed,
    required this.currentHr,
    required this.currentRmssd,
    required this.currentStage,
    required this.totalEpochs,
  });
}

class SleepEngine {
  final HealthDatabase _database = HealthDatabase();
  final NotificationService _notifications = NotificationService();

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  String? _activeSessionId;
  DateTime? _sessionStartTime;

  StreamSubscription<PolarAccData>? _accSub;
  StreamSubscription<PolarPpiData>? _ppiSub;

  final List<int> _epochPpiBuffer = [];
  final List<double> _epochVmuBuffer = [];
  DateTime? _epochStartTime;
  static const Duration _epochDuration = Duration(seconds: 30);

  final List<SleepEpoch> _sessionEpochs = [];
  final List<double> _allSessionRmssd = [];
  final List<double> _allSessionHr = [];

  double _baselineRestingHr = 60.0;
  double _baseline14DayRmssd = 42.0;

  double _latestHr = 0.0;
  double _latestRmssd = 0.0;
  SleepStage _latestStage = SleepStage.wake;

  final _statusController = StreamController<LiveSleepStatus>.broadcast();
  Stream<LiveSleepStatus> get statusStream => _statusController.stream;

  Timer? _statusTicker;

  Future<void> startSession({
    required Stream<PolarAccData> accStream,
    required Stream<PolarPpiData> ppiStream,
  }) async {
    if (_isTracking) return;

    _baselineRestingHr = await _database.getBaselineRestingHr();
    _baseline14DayRmssd = await _database.get14DayBaselineRmssd();

    _activeSessionId = const Uuid().v4();
    _sessionStartTime = DateTime.now();
    _isTracking = true;

    _sessionEpochs.clear();
    _allSessionRmssd.clear();
    _allSessionHr.clear();
    _epochPpiBuffer.clear();
    _epochVmuBuffer.clear();
    _epochStartTime = DateTime.now();

    _accSub = accStream.listen(_processAccData);
    _ppiSub = ppiStream.listen(_processPpiData);

    _statusTicker?.cancel();
    _statusTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _emitLiveStatus();
    });

    debugPrint('[SleepEngine] Started sleep tracking session: $_activeSessionId');
    _emitLiveStatus();
  }

  void _processAccData(PolarAccData data) {
    if (!_isTracking) return;

    for (final sample in data.samples) {
      final vmu = SedentaryEngine.calculateVmu(sample.x, sample.y, sample.z);
      _epochVmuBuffer.add(vmu);
    }

    _checkEpochCompletion();
  }

  void _processPpiData(PolarPpiData data) {
    if (!_isTracking) return;

    for (final sample in data.samples) {
      // Data Cleaning: Discard blockerBit == true, or PPI < 300ms or PPI > 2000ms
      if (HrvCalculator.isValidPpi(ppiMs: sample.ppi, blockerBit: sample.blockerBit)) {
        _epochPpiBuffer.add(sample.ppi);
      }
    }

    _checkEpochCompletion();
  }

  void _checkEpochCompletion() {
    final now = DateTime.now();
    _epochStartTime ??= now;

    if (now.difference(_epochStartTime!) >= _epochDuration) {
      _finalizeEpoch(now);
      _epochStartTime = now;
      _epochPpiBuffer.clear();
      _epochVmuBuffer.clear();
    }
  }

  void _finalizeEpoch(DateTime timestamp) {
    if (_epochPpiBuffer.isEmpty) return;

    // 1. Mean HR for the 30s epoch
    final meanHr = HrvCalculator.calculateMeanHr(_epochPpiBuffer);
    // 2. RMSSD for the 30s epoch
    final rmssd = HrvCalculator.calculateRmssd(_epochPpiBuffer);
    // 3. Movement Index: sum of VMU during the 30 seconds
    final movementIndex = _epochVmuBuffer.isNotEmpty
        ? _epochVmuBuffer.reduce((a, b) => a + b) / _epochVmuBuffer.length
        : 0.0;

    // 4. Classify sleep stage
    final stage = SleepStagingModel.classifyEpoch(
      epochMovementIndex: movementIndex,
      epochMeanHr: meanHr,
      epochRmssd: rmssd,
      baselineRestingHr: _baselineRestingHr,
      baselineRmssd: _baseline14DayRmssd,
    );

    _latestHr = meanHr;
    _latestRmssd = rmssd;
    _latestStage = stage;

    _allSessionHr.add(meanHr);
    if (rmssd > 0) _allSessionRmssd.add(rmssd);

    final epoch = SleepEpoch(
      sessionId: _activeSessionId!,
      timestamp: timestamp,
      stage: stage,
      meanHr: meanHr,
      rmssd: rmssd,
      movementIndex: movementIndex,
    );

    _sessionEpochs.add(epoch);
  }

  Future<SleepSession?> stopSession() async {
    if (!_isTracking || _activeSessionId == null || _sessionStartTime == null) return null;

    final endTime = DateTime.now();
    _isTracking = false;

    _accSub?.cancel();
    _accSub = null;
    _ppiSub?.cancel();
    _ppiSub = null;
    _statusTicker?.cancel();
    _statusTicker = null;

    // Finalize trailing partial epoch if sufficient samples exist
    if (_epochPpiBuffer.length >= 10) {
      _finalizeEpoch(endTime);
    }

    final durationMinutes = endTime.difference(_sessionStartTime!).inMinutes;

    // Count minutes per stage (each epoch is 0.5 minute / 30 seconds)
    int wakeCount = 0;
    int remCount = 0;
    int lightCount = 0;
    int deepCount = 0;

    for (final epoch in _sessionEpochs) {
      switch (epoch.stage) {
        case SleepStage.wake:
          wakeCount++;
          break;
        case SleepStage.rem:
          remCount++;
          break;
        case SleepStage.light:
          lightCount++;
          break;
        case SleepStage.deep:
          deepCount++;
          break;
      }
    }

    final wakeMinutes = (wakeCount * 0.5).round();
    final remMinutes = (remCount * 0.5).round();
    final lightMinutes = (lightCount * 0.5).round();
    final deepMinutes = (deepCount * 0.5).round();

    // Resting HR: 10th percentile or minimum sustained HR during the night
    double restingHr = _baselineRestingHr;
    if (_allSessionHr.isNotEmpty) {
      _allSessionHr.sort();
      // Use 10th percentile as clinical standard for overnight resting HR
      final p10Index = (_allSessionHr.length * 0.10).floor().clamp(0, _allSessionHr.length - 1);
      restingHr = _allSessionHr[p10Index];
    }

    // Overnight Average RMSSD
    final avgRmssd = _allSessionRmssd.isNotEmpty
        ? _allSessionRmssd.reduce((a, b) => a + b) / _allSessionRmssd.length
        : _baseline14DayRmssd;

    // Recovery Score Calculation
    final recovery = RecoveryScoreCalculator.calculate(
      durationMinutes: durationMinutes,
      deepMinutes: deepMinutes,
      remMinutes: remMinutes,
      nightRmssd: avgRmssd,
      baseline14DayRmssd: _baseline14DayRmssd,
    );

    final session = SleepSession(
      id: _activeSessionId!,
      startTime: _sessionStartTime!,
      endTime: endTime,
      durationMinutes: durationMinutes,
      wakeMinutes: wakeMinutes,
      remMinutes: remMinutes,
      lightMinutes: lightMinutes,
      deepMinutes: deepMinutes,
      restingHr: restingHr,
      avgRmssd: avgRmssd,
      recoveryScore: recovery.totalScore,
      syncedToHealth: false,
    );

    // Save to SQLite
    await _database.insertSleepSession(session);
    await _database.insertSleepEpochs(_sessionEpochs);

    // Send Morning Recovery Notification
    _notifications.showSleepSummary(
      recoveryScore: session.recoveryScore,
      durationHours: durationMinutes / 60.0,
      deepPercent: session.deepPercentage.round(),
    );

    _emitLiveStatus();
    return session;
  }

  void _emitLiveStatus() {
    if (_statusController.isClosed) return;

    final elapsed = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!)
        : Duration.zero;

    _statusController.add(LiveSleepStatus(
      isTracking: _isTracking,
      sessionId: _activeSessionId,
      elapsed: elapsed,
      currentHr: _latestHr,
      currentRmssd: _latestRmssd,
      currentStage: _latestStage,
      totalEpochs: _sessionEpochs.length,
    ));
  }

  void dispose() {
    _accSub?.cancel();
    _ppiSub?.cancel();
    _statusTicker?.cancel();
    _statusController.close();
  }
}
