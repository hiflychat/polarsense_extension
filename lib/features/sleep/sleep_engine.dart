import 'dart:async';
import 'dart:math';
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

    _accSub = accStream.listen(
      _processAccData,
      onError: (err) {
        debugPrint('[SleepEngine] ACC stream error: $err');
      },
      cancelOnError: false,
    );
    _ppiSub = ppiStream.listen(
      _processPpiData,
      onError: (err) {
        debugPrint('[SleepEngine] PPI stream error: $err');
      },
      cancelOnError: false,
    );

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
    // 1. Mean HR & RMSSD calculation
    double meanHr;
    double rmssd;

    final movementIndex = _epochVmuBuffer.isNotEmpty
        ? _epochVmuBuffer.reduce((a, b) => a + b) / _epochVmuBuffer.length
        : 0.0;

    if (_epochPpiBuffer.isNotEmpty) {
      meanHr = HrvCalculator.calculateMeanHr(_epochPpiBuffer);
      rmssd = HrvCalculator.calculateRmssd(_epochPpiBuffer);
    } else {
      // PPG optical contact momentarily dropped or noisy; carry forward latest state/baseline
      // to maintain a continuous unbroken 30s epoch timeline.
      meanHr = _latestHr > 0 ? _latestHr : _baselineRestingHr;
      rmssd = _latestRmssd > 0 ? _latestRmssd : _baseline14DayRmssd;
    }

    // 2. Classify sleep stage
    SleepStage stage;
    if (_epochPpiBuffer.isEmpty && movementIndex > 0.08) {
      stage = SleepStage.wake;
    } else {
      stage = SleepStagingModel.classifyEpoch(
        epochMovementIndex: movementIndex,
        epochMeanHr: meanHr,
        epochRmssd: rmssd,
        baselineRestingHr: _baselineRestingHr,
        baselineRmssd: _baseline14DayRmssd,
      );
    }

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
    if (_epochPpiBuffer.length >= 10 || _epochVmuBuffer.isNotEmpty) {
      _finalizeEpoch(endTime);
    }

    // Apply temporal continuity smoothing across whole session
    final smoothedEpochs = SleepStagingModel.smoothEpochs(_sessionEpochs);

    final durationMinutes = endTime.difference(_sessionStartTime!).inMinutes;

    // Count minutes per stage (each epoch is 0.5 minute / 30 seconds)
    int wakeCount = 0;
    int remCount = 0;
    int lightCount = 0;
    int deepCount = 0;

    for (final epoch in smoothedEpochs) {
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
        : 0.0;
    final hasHrvData = avgRmssd > 0;
    final actualSleepMinutes = remMinutes + lightMinutes + deepMinutes;

    // Recovery Score Calculation (evaluated against actual asleep minutes rather than awake time-in-bed)
    final recovery = RecoveryScoreCalculator.calculate(
      durationMinutes: actualSleepMinutes > 0 ? actualSleepMinutes : durationMinutes,
      deepMinutes: deepMinutes,
      remMinutes: remMinutes,
      nightRmssd: avgRmssd,
      baseline14DayRmssd: _baseline14DayRmssd,
      hasHrvData: hasHrvData,
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
      dataSource: SleepSession.sourceLiveAccPpi,
    );

    // Save to SQLite
    await _database.insertSleepSession(session);
    await _database.insertSleepEpochs(smoothedEpochs);

    // Send Morning Recovery Notification
    _notifications.showSleepSummary(
      recoveryScore: session.recoveryScore,
      durationHours: durationMinutes / 60.0,
      deepPercent: session.deepPercentage.round(),
    );

    _emitLiveStatus();
    return session;
  }

  /// Batch process an offline sleep session fetched from Polar Verity Sense internal flash memory.
  /// Converts raw HR/RR samples into 30-second epoch classifications, computes overnight RMSSD,
  /// 10th-percentile resting HR, recovery score, and writes to SQLite database.
  Future<SleepSession?> processOfflineExercise({
    required DateTime startTime,
    required PolarExerciseData exerciseData,
    String? customSessionId,
  }) async {
    if (exerciseData.samples.isEmpty) {
      debugPrint('[SleepEngine] Offline exercise has 0 samples');
      return null;
    }

    final sessionId = customSessionId ?? const Uuid().v4();
    _baselineRestingHr = await _database.getBaselineRestingHr();
    _baseline14DayRmssd = await _database.get14DayBaselineRmssd();

    final analyzed = analyzeOfflineSamples(
      sessionId: sessionId,
      startTime: startTime,
      exerciseData: exerciseData,
      priorBaselineRestingHr: _baselineRestingHr,
      priorBaseline14DayRmssd: _baseline14DayRmssd,
    );
    if (analyzed == null) return null;

    // Save to SQLite
    await _database.insertSleepSession(analyzed.session);
    await _database.insertSleepEpochs(analyzed.epochs);

    // Trigger Notification
    _notifications.showSleepSummary(
      recoveryScore: analyzed.session.recoveryScore,
      durationHours: analyzed.session.durationMinutes / 60.0,
      deepPercent: analyzed.session.deepPercentage.round(),
    );

    debugPrint(
      '[SleepEngine] Successfully imported offline sleep (${analyzed.session.dataSource}): '
      '${analyzed.session.durationFormatted}, recovery: ${analyzed.session.recoveryScore}',
    );
    return analyzed.session;
  }

  /// Pure offline analysis pipeline separated for deterministic unit testing and batch imports.
  static ({SleepSession session, List<SleepEpoch> epochs})? analyzeOfflineSamples({
    required String sessionId,
    required DateTime startTime,
    required PolarExerciseData exerciseData,
    double priorBaselineRestingHr = 60.0,
    double priorBaseline14DayRmssd = 42.0,
  }) {
    if (exerciseData.samples.isEmpty) return null;

    final intervalSec = exerciseData.interval > 0 ? exerciseData.interval : 1;
    final samples = exerciseData.samples;

    // Determine whether samples are genuine PPI/RR intervals (ms, > 250) or BPM heart rate (<= 250)
    final nonZeroSamples = samples.where((s) => s > 0).take(100).toList();
    final avgVal = nonZeroSamples.isNotEmpty
        ? nonZeroSamples.reduce((a, b) => a + b) / nonZeroSamples.length
        : 60.0;
    final isRrIntervals = avgVal > 250;

    final samplesPerEpoch = (30 / intervalSec).round().clamp(1, 300);
    final rawFeatures = <_OfflineEpochFeature>[];
    final allHr = <double>[];
    final allRmssd = <double>[];
    final allHrStds = <double>[];

    int totalSamples = samples.length;
    int epochIndex = 0;

    for (int i = 0; i < totalSamples; i += samplesPerEpoch) {
      final chunk = samples.sublist(i, min(i + samplesPerEpoch, totalSamples));
      if (chunk.isEmpty) continue;

      final epochTime = startTime.add(Duration(seconds: epochIndex * 30));
      final validPpi = <int>[];
      final epochHrList = <double>[];

      if (isRrIntervals) {
        for (final ppi in chunk) {
          if (ppi >= 300 && ppi <= 2000) {
            validPpi.add(ppi);
            epochHrList.add(60000.0 / ppi);
          }
        }
      } else {
        for (final hr in chunk) {
          if (hr >= 30 && hr <= 220) {
            epochHrList.add(hr.toDouble());
          }
        }
      }

      if (epochHrList.isEmpty) {
        epochIndex++;
        continue;
      }

      final meanHr = epochHrList.reduce((a, b) => a + b) / epochHrList.length;
      final maxHr = epochHrList.reduce(max);
      final minHr = epochHrList.reduce(min);
      final hrRange = maxHr - minHr;

      double hrStd = 0.0;
      if (epochHrList.length > 1) {
        double sumSq = 0.0;
        for (final h in epochHrList) {
          final d = h - meanHr;
          sumSq += d * d;
        }
        hrStd = sqrt(sumSq / (epochHrList.length - 1));
      }

      // True RMSSD is computed ONLY when genuine PPI/RR intervals are present;
      // 1Hz integer BPM cannot accurately measure beat-to-beat vagal RSA.
      final double rmssd = isRrIntervals ? HrvCalculator.calculateRmssd(validPpi) : 0.0;

      // Without ACC in offline exercise files, estimate movement proxy from rapid 30s HR surges
      final double movementIndex = hrRange > 12.0 ? (hrRange / 100.0) : 0.005;

      allHr.add(meanHr);
      allHrStds.add(hrStd);
      if (isRrIntervals && rmssd > 0) {
        allRmssd.add(rmssd);
      }

      rawFeatures.add(_OfflineEpochFeature(
        timestamp: epochTime,
        meanHr: meanHr,
        hrStd: hrStd,
        hrRange: hrRange,
        rmssd: rmssd,
        movementIndex: movementIndex,
      ));
      epochIndex++;
    }

    if (rawFeatures.isEmpty) {
      debugPrint('[SleepEngine] No valid sleep epochs generated from offline exercise');
      return null;
    }

    // Compute 10th-percentile resting HR for the session before staging epochs
    // so individuals with naturally lower (e.g., 48 bpm) or higher (e.g., 72 bpm) resting HR
    // are staged accurately even on their first recorded night.
    final sortedHrs = List<double>.from(allHr)..sort();
    final p10Idx = (sortedHrs.length * 0.10).floor().clamp(0, sortedHrs.length - 1);
    final sessionRestingHr = sortedHrs[p10Idx];
    final effectiveStagingBaselineHr = (priorBaselineRestingHr == 60.0)
        ? sessionRestingHr
        : (0.5 * priorBaselineRestingHr + 0.5 * sessionRestingHr);

    final sortedStds = List<double>.from(allHrStds)..sort();
    final medianHrStd = sortedStds[sortedStds.length ~/ 2];

    final generatedEpochs = <SleepEpoch>[];
    for (final f in rawFeatures) {
      final SleepStage stage;
      if (isRrIntervals) {
        stage = SleepStagingModel.classifyEpoch(
          epochMovementIndex: f.movementIndex,
          epochMeanHr: f.meanHr,
          epochRmssd: f.rmssd > 0 ? f.rmssd : priorBaseline14DayRmssd * 0.8,
          baselineRestingHr: effectiveStagingBaselineHr,
          baselineRmssd: priorBaseline14DayRmssd,
        );
      } else {
        stage = SleepStagingModel.classifyHrOnlyEpoch(
          epochMeanHr: f.meanHr,
          epochHrStd: f.hrStd,
          epochHrRange: f.hrRange,
          baselineRestingHr: effectiveStagingBaselineHr,
          medianHrStd: medianHrStd,
        );
      }

      generatedEpochs.add(SleepEpoch(
        sessionId: sessionId,
        timestamp: f.timestamp,
        stage: stage,
        meanHr: f.meanHr,
        rmssd: f.rmssd,
        movementIndex: f.movementIndex,
      ));
    }

    // Apply temporal continuity smoothing across whole offline recording
    final smoothedEpochs = SleepStagingModel.smoothEpochs(generatedEpochs);

    final totalDurationSec = samples.length * intervalSec;
    final durationMinutes = (totalDurationSec / 60).round();
    final endTime = startTime.add(Duration(seconds: totalDurationSec));

    int wakeCount = 0;
    int remCount = 0;
    int lightCount = 0;
    int deepCount = 0;

    for (final ep in smoothedEpochs) {
      switch (ep.stage) {
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
    final actualSleepMinutes = remMinutes + lightMinutes + deepMinutes;

    final avgRmssd = isRrIntervals && allRmssd.isNotEmpty
        ? allRmssd.reduce((a, b) => a + b) / allRmssd.length
        : 0.0;
    final hasHrvData = isRrIntervals && avgRmssd > 0;

    final recovery = RecoveryScoreCalculator.calculate(
      durationMinutes: actualSleepMinutes > 0 ? actualSleepMinutes : durationMinutes,
      deepMinutes: deepMinutes,
      remMinutes: remMinutes,
      nightRmssd: avgRmssd,
      baseline14DayRmssd: priorBaseline14DayRmssd,
      hasHrvData: hasHrvData,
    );

    final session = SleepSession(
      id: sessionId,
      startTime: startTime,
      endTime: endTime,
      durationMinutes: durationMinutes,
      wakeMinutes: wakeMinutes,
      remMinutes: remMinutes,
      lightMinutes: lightMinutes,
      deepMinutes: deepMinutes,
      restingHr: sessionRestingHr,
      avgRmssd: avgRmssd,
      recoveryScore: recovery.totalScore,
      syncedToHealth: false,
      dataSource: isRrIntervals
          ? SleepSession.sourceOfflinePpi
          : SleepSession.sourceOfflineHrOnly,
    );

    return (session: session, epochs: smoothedEpochs);
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

class _OfflineEpochFeature {
  final DateTime timestamp;
  final double meanHr;
  final double hrStd;
  final double hrRange;
  final double rmssd;
  final double movementIndex;

  const _OfflineEpochFeature({
    required this.timestamp,
    required this.meanHr,
    required this.hrStd,
    required this.hrRange,
    required this.rmssd,
    required this.movementIndex,
  });
}
