import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar/polar.dart';
import 'package:polarsense_extension/core/ble/polar_ble_manager.dart';
import 'package:polarsense_extension/core/database/models/sleep_record.dart';
import 'package:polarsense_extension/features/sleep/hrv_calculator.dart';
import 'package:polarsense_extension/features/sleep/recovery_score_calculator.dart';
import 'package:polarsense_extension/features/sleep/sleep_engine.dart';
import 'package:polarsense_extension/features/sleep/sleep_session_controller.dart';
import 'package:polarsense_extension/features/sleep/sleep_staging_model.dart';

void main() {
  group('Offline Sleep Processing & Analysis Tests', () {
    test('generateMockSleepExerciseData produces 7.5 hours of continuous 1-second samples', () {
      final exerciseData = PolarBleManager.generateMockSleepExerciseData();

      expect(exerciseData.interval, 1);
      // 7.5 hours * 3600 seconds = 27,000 samples
      expect(exerciseData.samples.length, 27000);

      // Verify samples are in valid RR interval range (ms)
      for (final s in exerciseData.samples) {
        expect(s, greaterThanOrEqualTo(500));
        expect(s, lessThanOrEqualTo(1500));
      }
    });

    test('Correctly identifies RR intervals (ms) vs HR (BPM) based on value threshold', () {
      // Case A: Optical PPG pulse-to-pulse intervals (ms)
      final rrSamples = [950, 970, 960, 940, 1010];
      final avgRr = rrSamples.reduce((a, b) => a + b) / rrSamples.length;
      final isRr = avgRr > 250;
      expect(isRr, isTrue);

      // Case B: Processed Heart Rate (BPM)
      final hrSamples = [62, 63, 61, 60, 64];
      final avgHr = hrSamples.reduce((a, b) => a + b) / hrSamples.length;
      final isHr = avgHr > 250;
      expect(isHr, isFalse);
    });

    test('30-second epoch chunking partitions 1-second samples into 30 samples per epoch', () {
      const intervalSec = 1;
      const samplesPerEpoch = 30 ~/ intervalSec;
      expect(samplesPerEpoch, 30);

      // 600 samples = 20 epochs
      final mockSamples = List.generate(600, (i) => 900 + (i % 50));
      int epochCount = 0;

      for (int i = 0; i < mockSamples.length; i += samplesPerEpoch) {
        final chunk = mockSamples.sublist(i, min(i + samplesPerEpoch, mockSamples.length));
        expect(chunk.length, 30);
        epochCount++;
      }

      expect(epochCount, 20);
    });

    test('Offline HR samples synthesized to equivalent RR intervals for RMSSD calculation', () {
      // 30 BPM samples at 60 bpm -> 1000 ms RR intervals
      final hrSamples = List.generate(30, (i) => i.isEven ? 60 : 62);
      final rrs = hrSamples.map((hr) => (60000.0 / hr).round()).toList();

      expect(rrs.first, 1000);
      expect(rrs[1], 968);

      final rmssd = HrvCalculator.calculateRmssd(rrs);
      expect(rmssd, closeTo(32.0, 1.0));
    });

    test('Full 7.5-hour offline mock session stages into Deep, Light, REM, and Wake', () {
      final exerciseData = PolarBleManager.generateMockSleepExerciseData();

      const baselineRestingHr = 58.0;
      const baselineRmssd = 42.0;

      final stageCounts = <SleepStage, int>{
        SleepStage.wake: 0,
        SleepStage.light: 0,
        SleepStage.deep: 0,
        SleepStage.rem: 0,
      };

      final allEpochHr = <double>[];
      final allEpochRmssd = <double>[];
      final generatedEpochs = <SleepEpoch>[];

      // Slicing into 900 30-second epochs
      for (int i = 0; i < exerciseData.samples.length; i += 30) {
        final chunk = exerciseData.samples.sublist(i, i + 30);
        final epochHrList = chunk.map((ppi) => 60000.0 / ppi).toList();
        final meanHr = epochHrList.reduce((a, b) => a + b) / epochHrList.length;
        final rmssd = HrvCalculator.calculateRmssd(chunk);

        final maxHr = epochHrList.reduce(max);
        final minHr = epochHrList.reduce(min);
        double movementIndex = 0.005;
        if (maxHr - minHr > 12.0) {
          movementIndex = (maxHr - minHr) / 100.0;
        }

        final stage = SleepStagingModel.classifyEpoch(
          epochMovementIndex: movementIndex,
          epochMeanHr: meanHr,
          epochRmssd: rmssd,
          baselineRestingHr: baselineRestingHr,
          baselineRmssd: baselineRmssd,
        );

        allEpochHr.add(meanHr);
        allEpochRmssd.add(rmssd);

        generatedEpochs.add(SleepEpoch(
          sessionId: 'mock-offline-session',
          timestamp: DateTime.now().add(Duration(seconds: (i ~/ 30) * 30)),
          stage: stage,
          meanHr: meanHr,
          rmssd: rmssd,
          movementIndex: movementIndex,
        ));
      }

      // Apply continuity smoother
      final smoothedEpochs = SleepStagingModel.smoothEpochs(generatedEpochs);
      for (final ep in smoothedEpochs) {
        stageCounts[ep.stage] = (stageCounts[ep.stage] ?? 0) + 1;
      }

      // Assert that all four stages are detected
      expect(stageCounts[SleepStage.wake]!, greaterThan(0));
      expect(stageCounts[SleepStage.deep]!, greaterThan(50)); // deep slow wave sleep
      expect(stageCounts[SleepStage.rem]!, greaterThan(50));   // rem sleep
      expect(stageCounts[SleepStage.light]!, greaterThan(50)); // light sleep

      // Assert resting HR (10th percentile)
      allEpochHr.sort();
      final p10Index = (allEpochHr.length * 0.10).floor();
      final restingHr = allEpochHr[p10Index];
      expect(restingHr, closeTo(52.0, 4.0));

      // Assert average RMSSD
      final avgRmssd = allEpochRmssd.reduce((a, b) => a + b) / allEpochRmssd.length;
      expect(avgRmssd, greaterThan(35.0));

      // Calculate recovery score
      final recovery = RecoveryScoreCalculator.calculate(
        durationMinutes: 450,
        deepMinutes: (stageCounts[SleepStage.deep]! * 0.5).round(),
        remMinutes: (stageCounts[SleepStage.rem]! * 0.5).round(),
        nightRmssd: avgRmssd,
        baseline14DayRmssd: baselineRmssd,
      );

      expect(recovery.totalScore, greaterThanOrEqualTo(80));
      expect(recovery.totalScore, lessThanOrEqualTo(100));
    });

    test('Deduplication logic accurately detects overlapping sessions within 15 minutes', () {
      final baseDate = DateTime(2026, 11, 10, 8, 0, 0);
      final existingSessions = [
        SleepSession(
          id: 'test-session-1',
          startTime: baseDate,
          endTime: baseDate.add(const Duration(hours: 7)),
          durationMinutes: 420,
          wakeMinutes: 20,
          remMinutes: 90,
          lightMinutes: 210,
          deepMinutes: 100,
          restingHr: 54,
          avgRmssd: 45,
          recoveryScore: 88,
          syncedToHealth: false,
        ),
      ];

      bool isAlreadyImported(DateTime entryDate) {
        return existingSessions.any((s) =>
            s.startTime.difference(entryDate).inMinutes.abs() < 15);
      }

      // Exact time -> true
      expect(isAlreadyImported(baseDate), isTrue);
      // 5 minutes difference -> true
      expect(isAlreadyImported(baseDate.add(const Duration(minutes: 5))), isTrue);
      // 2 hours difference -> false (new session)
      expect(isAlreadyImported(baseDate.add(const Duration(hours: 2))), isFalse);
    });

    test('OfflineSyncResult distinguishes errors, empty scans, and synced sessions', () {
      const errorResult = OfflineSyncResult(
        entriesFound: 0,
        errorMessage: 'SYSTEM_BUSY',
        diagnostics: {'u0Paths': []},
      );
      expect(errorResult.isSuccess, isFalse);
      expect(errorResult.errorMessage, 'SYSTEM_BUSY');

      final session = SleepSession(
        id: 'sense_20261112083000',
        startTime: DateTime(2026, 11, 12, 0, 30),
        endTime: DateTime(2026, 11, 12, 8, 0),
        durationMinutes: 450,
        wakeMinutes: 20,
        remMinutes: 100,
        lightMinutes: 230,
        deepMinutes: 100,
        restingHr: 54,
        avgRmssd: 48,
        recoveryScore: 90,
        syncedToHealth: false,
      );
      final okResult = OfflineSyncResult(
        session: session,
        entriesFound: 1,
        syncedCount: 1,
      );
      expect(okResult.isSuccess, isTrue);
      expect(okResult.syncedCount, 1);
    });

    test('SleepEngine.analyzeOfflineSamples stages Green-LED 1Hz HR data without fake RMSSD', () {
      // Simulate 7 hours (25,200 1Hz BPM samples) with Deep, REM, Light, and brief Wake
      final hrSamples = <int>[];
      final rand = Random(7);
      for (int epoch = 0; epoch < 840; epoch++) {
        for (int s = 0; s < 30; s++) {
          if (epoch < 20 || epoch >= 820) {
            // Wake onset & morning wake
            hrSamples.add(74 + rand.nextInt(5));
          } else if ((epoch >= 100 && epoch < 260) || (epoch >= 420 && epoch < 560)) {
            // Deep slow-wave sleep: calm low HR around 52-53 bpm
            hrSamples.add(52 + (s % 5 == 0 ? 1 : 0));
          } else if ((epoch >= 280 && epoch < 360) || (epoch >= 600 && epoch < 740)) {
            // REM sleep: phasic oscillation between 58 and 66 bpm
            hrSamples.add(59 + ((s % 6 < 3) ? 6 : 0) + rand.nextInt(2));
          } else {
            // Light sleep: intermediate ~56 bpm with mild drift
            hrSamples.add(56 + (s % 4 == 0 ? 2 : 0));
          }
        }
      }

      final analyzed = SleepEngine.analyzeOfflineSamples(
        sessionId: 'hr_only_test',
        startTime: DateTime(2026, 11, 11, 23, 30),
        exerciseData: PolarExerciseData(interval: 1, samples: hrSamples),
      );

      expect(analyzed, isNotNull);
      final session = analyzed!.session;
      expect(session.dataSource, SleepSession.sourceOfflineHrOnly);
      expect(session.isHrOnlyOffline, isTrue);
      expect(session.hasHrvData, isFalse);
      expect(session.avgRmssd, 0.0); // Does not fabricate PPI RMSSD from 1Hz BPM
      expect(session.deepMinutes, greaterThan(60));
      expect(session.lightMinutes, greaterThan(60));
      expect(session.remMinutes, greaterThan(60));
      expect(session.wakeMinutes, greaterThan(10));
      expect(session.recoveryScore, greaterThanOrEqualTo(80));
    });

    test('SleepEngine.analyzeOfflineSamples anchors first-night baseline to low RHR sleepers (48 bpm)', () {
      // Simulate a fit sleeper with 48 bpm resting HR on night 1 (prior default = 60 bpm)
      final ppiSamples = <int>[];
      for (int epoch = 0; epoch < 240; epoch++) {
        final targetHr = epoch < 120 ? 48.0 : 56.0; // Deep 48 bpm, Light/REM 56 bpm
        final basePpi = (60000.0 / targetHr).round();
        for (int s = 0; s < 30; s++) {
          final diff = epoch < 120 ? (s.isEven ? 30 : -30) : (s.isEven ? 18 : -18);
          ppiSamples.add(basePpi + diff);
        }
      }

      final analyzed = SleepEngine.analyzeOfflineSamples(
        sessionId: 'ppi_low_rhr_test',
        startTime: DateTime(2026, 11, 11, 23, 0),
        exerciseData: PolarExerciseData(interval: 1, samples: ppiSamples),
        priorBaselineRestingHr: 60.0,
        priorBaseline14DayRmssd: 42.0,
      );

      expect(analyzed, isNotNull);
      expect(analyzed!.session.dataSource, SleepSession.sourceOfflinePpi);
      expect(analyzed.session.hasHrvData, isTrue);
      expect(analyzed.session.restingHr, closeTo(48.0, 1.5));
      expect(analyzed.session.deepMinutes, greaterThan(30));
      expect(analyzed.session.remMinutes, greaterThan(30));
    });
  });
}
