import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:polarsense_extension/features/sedentary/sedentary_engine.dart';

void main() {
  group('SedentaryEngine VMU & Mathematical Tests', () {
    test('calculateVmu should return 0.0 for static 1.0g gravity vector', () {
      // 0, 0, 1000 mg = 1.0g
      final vmuZ = SedentaryEngine.calculateVmu(0, 0, 1000);
      expect(vmuZ, closeTo(0.0, 0.0001));

      // 1000, 0, 0 mg = 1.0g
      final vmuX = SedentaryEngine.calculateVmu(1000, 0, 0);
      expect(vmuX, closeTo(0.0, 0.0001));

      // Vector sum of (0.6g, 0.8g, 0g) = 1.0g
      final vmuTilted = SedentaryEngine.calculateVmu(600, 800, 0);
      expect(vmuTilted, closeTo(0.0, 0.0001));
    });

    test('calculateVmu should return correct dynamic component for arm movements', () {
      // 0, 0, 1250 mg = 1.25g -> VMU = |1.25 - 1.0| = 0.25g
      final vmuMoving = SedentaryEngine.calculateVmu(0, 0, 1250);
      expect(vmuMoving, closeTo(0.25, 0.0001));

      // 0, 0, 800 mg = 0.8g -> VMU = |0.8 - 1.0| = 0.20g
      final vmuDecel = SedentaryEngine.calculateVmu(0, 0, 800);
      expect(vmuDecel, closeTo(0.20, 0.0001));
    });

    test('Sedentary status getters and progress calculations', () {
      final status = SedentaryStatus(
        sedentarySeconds: 1800, // 30 minutes
        activeWalkingSeconds: 45,
        currentVmu: 0.02,
        state: PostureState.sedentary,
        alertThresholdMinutes: 60,
        hasTriggeredAlert: false,
        walkingPauseGraceCounter: 10,
      );

      expect(status.sedentaryMinutes, 30);
      expect(status.progressToAlert, closeTo(0.5, 0.01));
      expect(status.walkingResetProgress, closeTo(0.5, 0.01));
      expect(status.isWalkingGraceActive, isTrue);
    });

    test('Walking grace period is inactive when walking or when grace expires', () {
      final walkingStatus = SedentaryStatus(
        sedentarySeconds: 100,
        activeWalkingSeconds: 50,
        currentVmu: 0.20,
        state: PostureState.activeWalking,
        alertThresholdMinutes: 45,
        hasTriggeredAlert: false,
        walkingPauseGraceCounter: 15,
      );
      // When actively walking, grace is not active (user is actively moving)
      expect(walkingStatus.isWalkingGraceActive, isFalse);

      final expiredStatus = SedentaryStatus(
        sedentarySeconds: 100,
        activeWalkingSeconds: 0,
        currentVmu: 0.01,
        state: PostureState.sedentary,
        alertThresholdMinutes: 45,
        hasTriggeredAlert: false,
        walkingPauseGraceCounter: 0,
      );
      expect(expiredStatus.isWalkingGraceActive, isFalse);
    });

    test('Intermediate posture VMU between 0.04g and 0.15g indicates desk activity', () {
      // 70mg dynamic acceleration = 0.07g -> within intermediate desk typing range
      final vmuTyping = SedentaryEngine.calculateVmu(0, 0, 1070);
      expect(vmuTyping, closeTo(0.07, 0.001));
      expect(vmuTyping, greaterThanOrEqualTo(SedentaryEngine.sedentaryVmuThreshold));
      expect(vmuTyping, lessThan(SedentaryEngine.walkingVmuThreshold));
    });
  });
}
