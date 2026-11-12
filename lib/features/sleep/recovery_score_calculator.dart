import 'dart:math';

class RecoveryBreakdown {
  final int totalScore;
  final double durationScore;
  final double stageRatioScore;
  final double hrvScore;
  final double hrvFactor;
  final bool hasHrvData;
  final String statusDescription;

  RecoveryBreakdown({
    required this.totalScore,
    required this.durationScore,
    required this.stageRatioScore,
    required this.hrvScore,
    required this.hrvFactor,
    this.hasHrvData = true,
    required this.statusDescription,
  });
}

class RecoveryScoreCalculator {
  /// Computes 0 - 100 Nightly Recovery Score based on:
  /// - 30% Sleep Duration (Target 7-9 hours)
  /// - 30% Deep + REM Sleep Ratio (Target combined 35% - 50%)
  /// - 40% HRV / ANS Score (Night RMSSD / 14-Day Baseline RMSSD)
  /// When [hasHrvData] is false (HR-only offline mode without PPI),
  /// reweights equitably across observable components: 50% Duration + 50% Stage Ratio.
  static RecoveryBreakdown calculate({
    required int durationMinutes,
    required int deepMinutes,
    required int remMinutes,
    required double nightRmssd,
    required double baseline14DayRmssd,
    bool hasHrvData = true,
  }) {
    // 1. Duration Score (0 - 100)
    final durationHours = durationMinutes / 60.0;
    double durationScore;
    if (durationHours >= 7.0 && durationHours <= 9.0) {
      durationScore = 100.0;
    } else if (durationHours < 7.0) {
      // Linear penalty below 7h
      durationScore = max(0.0, (durationHours / 7.0) * 100.0);
    } else {
      // Mild decay above 9 hours (excessive sleep)
      durationScore = max(80.0, 100.0 - (durationHours - 9.0) * 10.0);
    }

    // 2. Stage Ratio Score (0 - 100)
    // Target combined Deep (15-25%) + REM (20-25%) => Total 35% - 50%
    final restorativeRatio = durationMinutes > 0
        ? (deepMinutes + remMinutes) / durationMinutes
        : 0.0;

    double stageRatioScore;
    if (restorativeRatio >= 0.35 && restorativeRatio <= 0.50) {
      stageRatioScore = 100.0;
    } else if (restorativeRatio < 0.35) {
      stageRatioScore = max(0.0, (restorativeRatio / 0.35) * 100.0);
    } else {
      stageRatioScore = 95.0; // Excellent restorative proportion
    }

    // 3. HRV / ANS Score (0 - 100)
    final includeHrv = hasHrvData && nightRmssd > 0;
    double hrvFactor = 0.0;
    double hrvScore = 0.0;
    double totalComposite;

    if (includeHrv) {
      final effectiveBaseline = baseline14DayRmssd > 0 ? baseline14DayRmssd : 42.0;
      hrvFactor = nightRmssd / effectiveBaseline;

      // Normalizing HRV factor:
      // Factor 1.0 (baseline) -> 75
      // Factor >= 1.333 -> 100
      // Factor 0.50 -> 37.5
      hrvScore = (hrvFactor * 75.0).clamp(0.0, 100.0);

      // Composite Weighted Sum: 30% Duration + 30% Stage Ratio + 40% HRV
      totalComposite = (0.30 * durationScore) +
          (0.30 * stageRatioScore) +
          (0.40 * hrvScore);
    } else {
      // Honest reweighting when genuine beat-to-beat PPI HRV is unavailable
      totalComposite = (0.50 * durationScore) + (0.50 * stageRatioScore);
    }

    final finalScore = totalComposite.round().clamp(0, 100);

    String status;
    if (finalScore >= 85) {
      status = 'Optimal Recovery';
    } else if (finalScore >= 70) {
      status = 'Good Recovery';
    } else if (finalScore >= 50) {
      status = 'Moderate Recovery';
    } else {
      status = 'Suboptimal / High Fatigue';
    }

    return RecoveryBreakdown(
      totalScore: finalScore,
      durationScore: durationScore,
      stageRatioScore: stageRatioScore,
      hrvScore: hrvScore,
      hrvFactor: hrvFactor,
      hasHrvData: includeHrv,
      statusDescription: status,
    );
  }
}
