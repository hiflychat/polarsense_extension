import 'package:flutter_test/flutter_test.dart';
import 'package:polarsense_extension/core/database/models/sleep_record.dart';
import 'package:polarsense_extension/features/sleep/sleep_diagnostics.dart';
import 'package:polarsense_extension/features/sleep/sleep_staging_model.dart';
import 'package:polarsense_extension/features/sleep/recovery_score_calculator.dart';

void main() {
  group('SleepStagingModel Classification Tests', () {
    const baselineHr = 60.0;
    const baselineRmssd = 40.0;

    test('Classifies Wake when movement is high', () {
      final stage = SleepStagingModel.classifyEpoch(
        epochMovementIndex: 0.12, // > 0.08g
        epochMeanHr: 62.0,
        epochRmssd: 40.0,
        baselineRestingHr: baselineHr,
        baselineRmssd: baselineRmssd,
      );
      expect(stage, SleepStage.wake);
    });

    test('Classifies Wake when heart rate is elevated above baseline + 15 bpm', () {
      final stage = SleepStagingModel.classifyEpoch(
        epochMovementIndex: 0.02,
        epochMeanHr: 78.0, // > 60 + 15
        epochRmssd: 35.0,
        baselineRestingHr: baselineHr,
        baselineRmssd: baselineRmssd,
      );
      expect(stage, SleepStage.wake);
    });

    test('Classifies Deep Sleep when movement is minimal, HR is low, and RMSSD is elevated', () {
      final stage = SleepStagingModel.classifyEpoch(
        epochMovementIndex: 0.005, // < 0.01g
        epochMeanHr: 58.0,         // <= 60 + 5
        epochRmssd: 52.0,          // >= 1.2 * 40 = 48.0
        baselineRestingHr: baselineHr,
        baselineRmssd: baselineRmssd,
      );
      expect(stage, SleepStage.deep);
    });

    test('Classifies REM Sleep when movement is low and HR shows autonomic variance', () {
      final stage = SleepStagingModel.classifyEpoch(
        epochMovementIndex: 0.012, // < 0.02g
        epochMeanHr: 64.0,         // > baseline 60.0
        epochRmssd: 38.0,          // between 0.7 and 1.2 * baseline
        baselineRestingHr: baselineHr,
        baselineRmssd: baselineRmssd,
      );
      expect(stage, SleepStage.rem);
    });

    test('Classifies Light Sleep as intermediate default state', () {
      final stage = SleepStagingModel.classifyEpoch(
        epochMovementIndex: 0.04,
        epochMeanHr: 62.0,
        epochRmssd: 42.0,
        baselineRestingHr: baselineHr,
        baselineRmssd: baselineRmssd,
      );
      expect(stage, SleepStage.light);
    });
  });

  group('SleepStagingModel Temporal Smoothing Tests', () {
    final t0 = DateTime.now();

    test('Eliminates isolated 30-second stage flicker between identical stages', () {
      final epochs = [
        SleepEpoch(sessionId: 's1', timestamp: t0, stage: SleepStage.deep, meanHr: 54, rmssd: 55, movementIndex: 0.005),
        SleepEpoch(sessionId: 's1', timestamp: t0.add(const Duration(seconds: 30)), stage: SleepStage.light, meanHr: 55, rmssd: 50, movementIndex: 0.005),
        SleepEpoch(sessionId: 's1', timestamp: t0.add(const Duration(seconds: 60)), stage: SleepStage.deep, meanHr: 54, rmssd: 54, movementIndex: 0.005),
      ];

      final smoothed = SleepStagingModel.smoothEpochs(epochs);
      expect(smoothed[0].stage, SleepStage.deep);
      expect(smoothed[1].stage, SleepStage.deep); // Smoothed from light to deep
      expect(smoothed[2].stage, SleepStage.deep);
    });

    test('Preserves true motor arousals and heart rate spikes as Wake', () {
      final epochs = [
        SleepEpoch(sessionId: 's1', timestamp: t0, stage: SleepStage.deep, meanHr: 54, rmssd: 55, movementIndex: 0.005),
        SleepEpoch(sessionId: 's1', timestamp: t0.add(const Duration(seconds: 30)), stage: SleepStage.wake, meanHr: 82, rmssd: 25, movementIndex: 0.09),
        SleepEpoch(sessionId: 's1', timestamp: t0.add(const Duration(seconds: 60)), stage: SleepStage.deep, meanHr: 54, rmssd: 54, movementIndex: 0.005),
      ];

      final smoothed = SleepStagingModel.smoothEpochs(epochs);
      expect(smoothed[0].stage, SleepStage.deep);
      expect(smoothed[1].stage, SleepStage.wake); // Preserved because movement > 0.06 & HR >= 80
      expect(smoothed[2].stage, SleepStage.deep);
    });
  });

  group('RecoveryScoreCalculator Tests', () {
    test('Calculates near 100 for optimal sleep duration, stages, and HRV', () {
      final breakdown = RecoveryScoreCalculator.calculate(
        durationMinutes: 480, // 8.0 hours (optimal 7-9h)
        deepMinutes: 96,     // 20%
        remMinutes: 105,     // 22% -> Combined = 42% (optimal 35-50%)
        nightRmssd: 56.0,    // factor = 56 / 42 = 1.33 (> 1.25 -> 100)
        baseline14DayRmssd: 42.0,
      );

      expect(breakdown.durationScore, closeTo(100.0, 0.1));
      expect(breakdown.stageRatioScore, closeTo(100.0, 0.1));
      expect(breakdown.hrvScore, closeTo(100.0, 0.1));
      expect(breakdown.totalScore, closeTo(100, 1));
      expect(breakdown.statusDescription, 'Optimal Recovery');
    });

    test('Scales down proportionally for short duration and low HRV', () {
      final breakdown = RecoveryScoreCalculator.calculate(
        durationMinutes: 240, // 4 hours -> durationScore ~ 57.1
        deepMinutes: 20,
        remMinutes: 20,      // Combined = 40m / 240m = 16.6% -> stageScore ~ 47.6
        nightRmssd: 25.0,    // factor = 25 / 50 = 0.5 -> hrvScore ~ 37.5
        baseline14DayRmssd: 50.0,
      );

      expect(breakdown.totalScore, lessThan(55));
      expect(breakdown.statusDescription, anyOf('Moderate Recovery', 'Suboptimal / High Fatigue'));
    });

    test('Reweights 50/50 when HRV is unavailable (HR-only offline mode)', () {
      final breakdown = RecoveryScoreCalculator.calculate(
        durationMinutes: 480, // 8h -> 100
        deepMinutes: 90,
        remMinutes: 100,      // 190/480 = 39.6% -> 100
        nightRmssd: 0.0,
        baseline14DayRmssd: 42.0,
        hasHrvData: false,
      );

      expect(breakdown.hasHrvData, isFalse);
      expect(breakdown.durationScore, closeTo(100.0, 0.1));
      expect(breakdown.stageRatioScore, closeTo(100.0, 0.1));
      expect(breakdown.totalScore, 100);
    });
  });

  group('SleepStagingModel HR-Only Offline Staging Tests', () {
    test('Classifies Deep, REM, Light, and Wake accurately from 1Hz HR features', () {
      const baselineHr = 54.0;
      const medianStd = 1.4;

      expect(
        SleepStagingModel.classifyHrOnlyEpoch(
          epochMeanHr: 55.0,
          epochHrStd: 0.9,
          epochHrRange: 2.0,
          baselineRestingHr: baselineHr,
          medianHrStd: medianStd,
        ),
        SleepStage.deep,
      );

      expect(
        SleepStagingModel.classifyHrOnlyEpoch(
          epochMeanHr: 61.0,
          epochHrStd: 2.4,
          epochHrRange: 7.0,
          baselineRestingHr: baselineHr,
          medianHrStd: medianStd,
        ),
        SleepStage.rem,
      );

      expect(
        SleepStagingModel.classifyHrOnlyEpoch(
          epochMeanHr: 74.0,
          epochHrStd: 3.1,
          epochHrRange: 9.0,
          baselineRestingHr: baselineHr,
          medianHrStd: medianStd,
        ),
        SleepStage.wake,
      );

      expect(
        SleepStagingModel.classifyHrOnlyEpoch(
          epochMeanHr: 58.0,
          epochHrStd: 1.5,
          epochHrRange: 4.0,
          baselineRestingHr: baselineHr,
          medianHrStd: medianStd,
        ),
        SleepStage.light,
      );
    });

    test('Preserves Deep Sleep under real-world breathing noise (0.015g) and RSA swings (6 bpm)', () {
      // PPI/ACC mode with 0.016g resting arm/breathing motion must classify Deep (not Light)
      expect(
        SleepStagingModel.classifyEpoch(
          epochMovementIndex: 0.016,
          epochMeanHr: 55.0,
          epochRmssd: 46.0, // 1.15x of 40.0 baseline
          baselineRestingHr: 58.0,
          baselineRmssd: 40.0,
        ),
        SleepStage.deep,
      );

      // HR-only mode with normal 6 bpm slow-wave breathing RSA oscillation must still classify Deep
      expect(
        SleepStagingModel.classifyHrOnlyEpoch(
          epochMeanHr: 56.0,
          epochHrStd: 1.4,
          epochHrRange: 6.0,
          baselineRestingHr: 54.0,
          medianHrStd: 1.5,
        ),
        SleepStage.deep,
      );
    });
  });

  group('SleepDiagnosticsAnalyzer Tests', () {
    test('Identifies elevated 1st-half HR and subtle motion attribution when Deep is low', () {
      final t0 = DateTime(2026, 11, 15, 23, 30);
      final epochs = List.generate(120, (i) {
        final firstHalf = i < 60;
        return SleepEpoch(
          sessionId: 'diag_test',
          timestamp: t0.add(Duration(seconds: i * 30)),
          stage: i < 4 ? SleepStage.deep : SleepStage.light,
          meanHr: firstHalf ? 64.0 : 59.0,
          rmssd: 38.0,
          movementIndex: 0.015, // Falls inside 0.01-0.025g subtle motion band
        );
      });

      final session = SleepSession(
        id: 'diag_test',
        startTime: t0,
        endTime: t0.add(const Duration(minutes: 60)),
        durationMinutes: 60,
        wakeMinutes: 0,
        remMinutes: 0,
        lightMinutes: 58,
        deepMinutes: 2,
        restingHr: 58.0,
        avgRmssd: 38.0,
        recoveryScore: 42,
      );

      final report = SleepDiagnosticsAnalyzer.analyze(session, epochs);
      expect(report.longestDeepBoutMinutes, 2);
      expect(report.subtleMotionSharePct, closeTo(100.0, 0.1));
      expect(report.firstHalfMeanHr, closeTo(64.0, 0.1));
      expect(report.secondHalfMeanHr, closeTo(59.0, 0.1));
      expect(report.insights, contains(SleepInsightCode.lowDeepPossibleStrictFilter));
      expect(report.insights, contains(SleepInsightCode.elevatedFirstHalfHr));
    });
  });
}
