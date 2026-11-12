import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar/polar.dart';
import 'package:polarsense_extension/core/ble/polar_ble_manager.dart';
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
        activeWalkingSeconds: 30, // 30s of active movement
        currentVmu: 0.02,
        state: PostureState.sedentary,
        alertThresholdMinutes: 60,
        hasTriggeredAlert: false,
        walkingPauseGraceCounter: 10,
      );

      expect(status.sedentaryMinutes, 30);
      expect(status.progressToAlert, closeTo(0.5, 0.01));
      expect(status.walkingResetProgress, closeTo(0.5, 0.01)); // 30s / 60s = 0.5
      expect(status.isWalkingGraceActive, isTrue);
    });

    test('Active movement grace period is inactive during active movement or when grace expires', () {
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

      final armActiveStatus = SedentaryStatus(
        sedentarySeconds: 100,
        activeWalkingSeconds: 40,
        currentVmu: 0.10,
        state: PostureState.activeArmMove, // Washing hair, chores, stretching
        alertThresholdMinutes: 45,
        hasTriggeredAlert: false,
        walkingPauseGraceCounter: 15,
      );
      // When actively moving arms (e.g. washing hair), grace is not active (active movement in progress)
      expect(armActiveStatus.isWalkingGraceActive, isFalse);

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

    test('Desk typing vs active arm movement (washing hair/chores) classification', () {
      // 50mg dynamic acceleration = 0.050g -> within desk typing range (0.035g - 0.070g)
      final vmuTyping = SedentaryEngine.calculateVmu(0, 0, 1050);
      expect(vmuTyping, closeTo(0.050, 0.001));
      expect(vmuTyping, greaterThanOrEqualTo(SedentaryEngine.sedentaryVmuThreshold));
      expect(vmuTyping, lessThan(SedentaryEngine.deskTypingVmuThreshold));

      // 100mg dynamic acceleration = 0.100g -> within active arm movement range (washing hair, stretching)
      final vmuHairWashing = SedentaryEngine.calculateVmu(0, 0, 1100);
      expect(vmuHairWashing, closeTo(0.100, 0.001));
      expect(vmuHairWashing, greaterThanOrEqualTo(SedentaryEngine.deskTypingVmuThreshold));
      expect(vmuHairWashing, lessThan(SedentaryEngine.activeArmVmuThreshold));
    });

    test('PolarBleManager.resolveOptimalAccSettings selects 26Hz/52Hz balanced settings', () {
      // Case 1: Sensor exposes 26..416 Hz -> must pick 26 Hz (halves BLE/UI load) & 8g
      final multiRate = PolarSensorSetting.fromJson({
        'settings': {
          'SAMPLE_RATE': [26, 52, 104, 208, 416],
          'RANGE': [2, 4, 8, 16],
          'RESOLUTION': [16],
          'CHANNELS': [3],
        },
      });
      final optMulti = PolarBleManager.resolveOptimalAccSettings(multiRate);
      expect(optMulti.settings[PolarSettingType.sampleRate], [26]);
      expect(optMulti.settings[PolarSettingType.range], [8]);
      expect(optMulti.settings[PolarSettingType.resolution], [16]);
      expect(optMulti.settings[PolarSettingType.channels], [3]);

      // Case 2: Standard Verity Sense exposes only 52 Hz -> picks 52 Hz
      final standardOnly = PolarSensorSetting({
        PolarSettingType.sampleRate: 52,
        PolarSettingType.range: 8,
      });
      final optStd = PolarBleManager.resolveOptimalAccSettings(standardOnly);
      expect(optStd.settings[PolarSettingType.sampleRate], [52]);
      expect(optStd.settings[PolarSettingType.range], [8]);

      // Case 3: Fallback when available is null
      final optFallback = PolarBleManager.resolveOptimalAccSettings(null);
      expect(optFallback.settings.containsKey(PolarSettingType.sampleRate), isTrue);
    });
  });
}
