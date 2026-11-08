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
      );

      expect(status.sedentaryMinutes, 30);
      expect(status.progressToAlert, closeTo(0.5, 0.01));
      expect(status.walkingResetProgress, closeTo(0.5, 0.01));
    });
  });
}
