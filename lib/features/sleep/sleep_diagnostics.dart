import '../../core/database/models/sleep_record.dart';

enum SleepInsightCode {
  healthyRestorative,
  lowDeepPossibleStrictFilter,
  elevatedFirstHalfHr,
  narrowNocturnalDip,
  fragmentedWakeOrMotion,
  hrOnlyCalibrationNote,
}

class SleepDiagnosticReport {
  final double p10Hr;
  final double medianHr;
  final double maxHr;
  final double firstHalfMeanHr;
  final double secondHalfMeanHr;
  final bool hasMotionTelemetry;
  final double meanMovementG;
  final double subtleMotionSharePct;
  final double highMotionSharePct;
  final int longestDeepBoutMinutes;
  final List<SleepInsightCode> insights;

  const SleepDiagnosticReport({
    required this.p10Hr,
    required this.medianHr,
    required this.maxHr,
    required this.firstHalfMeanHr,
    required this.secondHalfMeanHr,
    required this.hasMotionTelemetry,
    required this.meanMovementG,
    required this.subtleMotionSharePct,
    required this.highMotionSharePct,
    required this.longestDeepBoutMinutes,
    required this.insights,
  });

  double get nocturnalHrDrop => (medianHr - p10Hr).clamp(0.0, 60.0);
  double get firstToSecondHalfDelta => firstHalfMeanHr - secondHalfMeanHr;
}

class SleepDiagnosticsAnalyzer {
  /// Computes per-night physiological & algorithmic diagnostics directly from a
  /// [SleepSession] and its 30-second [SleepEpoch] timeline.
  static SleepDiagnosticReport analyze(
    SleepSession session,
    List<SleepEpoch> epochs,
  ) {
    if (epochs.isEmpty) {
      return SleepDiagnosticReport(
        p10Hr: session.restingHr,
        medianHr: session.restingHr,
        maxHr: session.restingHr,
        firstHalfMeanHr: session.restingHr,
        secondHalfMeanHr: session.restingHr,
        hasMotionTelemetry: false,
        meanMovementG: 0.0,
        subtleMotionSharePct: 0.0,
        highMotionSharePct: 0.0,
        longestDeepBoutMinutes: session.deepMinutes,
        insights: [
          if (session.isHrOnlyOffline) SleepInsightCode.hrOnlyCalibrationNote,
        ],
      );
    }

    final hrs = epochs.map((e) => e.meanHr).where((h) => h > 25 && h < 230).toList();
    final sortedHrs = List<double>.from(hrs)..sort();
    final p10Hr = sortedHrs.isNotEmpty
        ? sortedHrs[(sortedHrs.length * 0.10).floor().clamp(0, sortedHrs.length - 1)]
        : session.restingHr;
    final medianHr = sortedHrs.isNotEmpty
        ? sortedHrs[sortedHrs.length ~/ 2]
        : session.restingHr;
    final maxHr = sortedHrs.isNotEmpty ? sortedHrs.last : session.restingHr;

    final mid = epochs.length ~/ 2;
    final firstHalf = epochs.take(mid > 0 ? mid : 1).map((e) => e.meanHr).toList();
    final secondHalf = epochs.skip(mid > 0 ? mid : 0).map((e) => e.meanHr).toList();
    final firstHalfMeanHr = firstHalf.isNotEmpty
        ? firstHalf.reduce((a, b) => a + b) / firstHalf.length
        : medianHr;
    final secondHalfMeanHr = secondHalf.isNotEmpty
        ? secondHalf.reduce((a, b) => a + b) / secondHalf.length
        : medianHr;

    final hasMotionTelemetry =
        epochs.any((e) => (e.movementIndex - 0.005).abs() > 0.0001);
    final meanMovementG = epochs.map((e) => e.movementIndex).reduce((a, b) => a + b) /
        epochs.length;
    final subtleMotionCount = epochs
        .where((e) => e.movementIndex >= 0.01 && e.movementIndex < 0.025)
        .length;
    final highMotionCount = epochs.where((e) => e.movementIndex >= 0.025).length;

    final subtleMotionSharePct = (subtleMotionCount / epochs.length) * 100.0;
    final highMotionSharePct = (highMotionCount / epochs.length) * 100.0;

    int maxDeepEpochs = 0;
    int currentDeepEpochs = 0;
    for (final ep in epochs) {
      if (ep.stage == SleepStage.deep) {
        currentDeepEpochs++;
        if (currentDeepEpochs > maxDeepEpochs) {
          maxDeepEpochs = currentDeepEpochs;
        }
      } else {
        currentDeepEpochs = 0;
      }
    }
    final longestDeepBoutMinutes = (maxDeepEpochs * 0.5).round();

    final insights = <SleepInsightCode>[];
    final deepPct = session.deepPercentage;

    if (deepPct >= 13.0 && session.remPercentage >= 15.0 && session.sleepEfficiency >= 85.0) {
      insights.add(SleepInsightCode.healthyRestorative);
    }

    if (deepPct < 10.0 && (subtleMotionSharePct >= 20.0 || session.isHrOnlyOffline)) {
      insights.add(SleepInsightCode.lowDeepPossibleStrictFilter);
    }

    if (firstHalfMeanHr - secondHalfMeanHr > 1.5) {
      insights.add(SleepInsightCode.elevatedFirstHalfHr);
    }

    if (medianHr - p10Hr < 3.0) {
      insights.add(SleepInsightCode.narrowNocturnalDip);
    }

    if (session.sleepEfficiency < 82.0 || highMotionSharePct > 25.0) {
      insights.add(SleepInsightCode.fragmentedWakeOrMotion);
    }

    if (session.isHrOnlyOffline && !insights.contains(SleepInsightCode.hrOnlyCalibrationNote)) {
      insights.add(SleepInsightCode.hrOnlyCalibrationNote);
    }

    return SleepDiagnosticReport(
      p10Hr: p10Hr,
      medianHr: medianHr,
      maxHr: maxHr,
      firstHalfMeanHr: firstHalfMeanHr,
      secondHalfMeanHr: secondHalfMeanHr,
      hasMotionTelemetry: hasMotionTelemetry,
      meanMovementG: meanMovementG,
      subtleMotionSharePct: subtleMotionSharePct,
      highMotionSharePct: highMotionSharePct,
      longestDeepBoutMinutes: longestDeepBoutMinutes,
      insights: insights,
    );
  }
}
