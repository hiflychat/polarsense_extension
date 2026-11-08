import 'dart:math';

class HrvCalculator {
  /// Computes RMSSD (Root Mean Square of Successive Differences) in ms
  /// RMSSD = sqrt( 1 / (M-1) * sum((PPI[k+1] - PPI[k])^2) )
  static double calculateRmssd(List<int> validPpiMs) {
    if (validPpiMs.length < 2) return 0.0;

    double sumSquaredDiffs = 0.0;
    int count = validPpiMs.length - 1;

    for (int i = 0; i < count; i++) {
      final diff = validPpiMs[i + 1] - validPpiMs[i];
      sumSquaredDiffs += diff * diff;
    }

    return sqrt(sumSquaredDiffs / count);
  }

  /// Computes SDNN (Standard Deviation of NN/PPI intervals) in ms
  static double calculateSdnn(List<int> validPpiMs) {
    if (validPpiMs.length < 2) return 0.0;

    final mean = validPpiMs.reduce((a, b) => a + b) / validPpiMs.length;
    double sumVariance = 0.0;

    for (final ppi in validPpiMs) {
      final diff = ppi - mean;
      sumVariance += diff * diff;
    }

    return sqrt(sumVariance / (validPpiMs.length - 1));
  }

  /// Computes Mean Heart Rate in BPM from PPI sequence
  static double calculateMeanHr(List<int> validPpiMs) {
    if (validPpiMs.isEmpty) return 0.0;
    final meanPpi = validPpiMs.reduce((a, b) => a + b) / validPpiMs.length;
    if (meanPpi <= 0) return 0.0;
    return 60000.0 / meanPpi;
  }

  /// Validates and cleans raw PPI samples according to the spec:
  /// Discard if blockerBit is true or if PPI < 300ms or PPI > 2000ms
  static bool isValidPpi({required int ppiMs, required bool blockerBit}) {
    if (blockerBit) return false;
    if (ppiMs < 300 || ppiMs > 2000) return false;
    return true;
  }
}
