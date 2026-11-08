import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:polarsense_extension/features/sleep/hrv_calculator.dart';

void main() {
  group('HrvCalculator Mathematical Tests', () {
    test('calculateRmssd calculates correct RMSSD for known intervals', () {
      // Intervals: [800, 850, 820, 860]
      // Successive diffs: +50, -30, +40
      // Squared diffs: 2500, 900, 1600 -> sum = 5000
      // N = 4, pairs = 3 -> mean squared = 5000 / 3 = 1666.6667
      // sqrt(1666.6667) = 40.8248...
      final ppiList = [800, 850, 820, 860];
      final rmssd = HrvCalculator.calculateRmssd(ppiList);
      expect(rmssd, closeTo(40.8248, 0.001));
    });

    test('calculateMeanHr calculates correct BPM', () {
      // 1000ms PPI -> 60 bpm
      expect(HrvCalculator.calculateMeanHr([1000, 1000]), closeTo(60.0, 0.01));
      // 750ms PPI -> 80 bpm
      expect(HrvCalculator.calculateMeanHr([750, 750]), closeTo(80.0, 0.01));
      // Empty list returns 0.0
      expect(HrvCalculator.calculateMeanHr([]), 0.0);
    });

    test('isValidPpi discards blockerBit and outliers outside [300, 2000] ms', () {
      // Blocker bit true -> must discard
      expect(HrvCalculator.isValidPpi(ppiMs: 800, blockerBit: true), isFalse);

      // Too fast (< 300ms, > 200 bpm) -> discard
      expect(HrvCalculator.isValidPpi(ppiMs: 250, blockerBit: false), isFalse);

      // Too slow (> 2000ms, < 30 bpm) -> discard
      expect(HrvCalculator.isValidPpi(ppiMs: 2100, blockerBit: false), isFalse);

      // Normal physiological PPI -> valid
      expect(HrvCalculator.isValidPpi(ppiMs: 850, blockerBit: false), isTrue);
      expect(HrvCalculator.isValidPpi(ppiMs: 300, blockerBit: false), isTrue);
      expect(HrvCalculator.isValidPpi(ppiMs: 2000, blockerBit: false), isTrue);
    });
  });
}
