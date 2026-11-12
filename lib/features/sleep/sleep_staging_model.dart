import '../../core/database/models/sleep_record.dart';

class SleepStagingModel {
  /// Classifies a 30-second epoch into a SleepStage based on movement, HR, and RMSSD
  /// compared against the user's personal resting baseline.
  static SleepStage classifyEpoch({
    required double epochMovementIndex,
    required double epochMeanHr,
    required double epochRmssd,
    required double baselineRestingHr,
    required double baselineRmssd,
  }) {
    // 1. Wake condition: high body/arm movement or elevated heart rate
    if (epochMovementIndex > 0.08 || epochMeanHr > (baselineRestingHr + 15.0)) {
      return SleepStage.wake;
    }

    // 2. Deep Sleep (Slow Wave Sleep):
    // Characterized by minimal movement, suppressed HR, and high parasympathetic tone (elevated RMSSD)
    if (epochMovementIndex < 0.01 &&
        epochMeanHr <= (baselineRestingHr + 5.0) &&
        epochRmssd >= (1.2 * baselineRmssd)) {
      return SleepStage.deep;
    }

    // 3. REM Sleep:
    // Muscle atonia (negligible movement < 0.02g), but autonomic activation causes
    // variable HR and lower RMSSD relative to deep sleep.
    if (epochMovementIndex < 0.02 &&
        epochMeanHr > baselineRestingHr &&
        epochRmssd < (1.2 * baselineRmssd) &&
        epochRmssd >= (0.7 * baselineRmssd)) {
      return SleepStage.rem;
    }

    // 4. Light Sleep: default transitional stage
    return SleepStage.light;
  }

  /// Classifies a 30-second epoch when ONLY 1Hz/periodic Heart Rate (BPM) is available
  /// (e.g., Polar Verity Sense Green-LED standalone offline mode without ACC or raw PPI).
  ///
  /// Uses personal nocturnal resting HR baseline and within-epoch HR volatility (std & range):
  /// - Deep Sleep (SWS): lowest HR near nocturnal nadir with minimal sympathetic variability.
  /// - REM Sleep: mildly elevated HR above resting nadir accompanied by phasic HR variability/oscillation.
  /// - Wake: sustained HR elevation (> +15 bpm) or rapid surge (> 12 bpm range within 30s).
  /// - Light Sleep: intermediate transitional NREM periods.
  static SleepStage classifyHrOnlyEpoch({
    required double epochMeanHr,
    required double epochHrStd,
    required double epochHrRange,
    required double baselineRestingHr,
    required double medianHrStd,
  }) {
    if (epochHrRange > 12.0 || epochMeanHr > (baselineRestingHr + 15.0)) {
      return SleepStage.wake;
    }

    final steadyStdThreshold = medianHrStd > 0
        ? (medianHrStd * 1.0).clamp(1.0, 2.2)
        : 1.5;
    final remStdThreshold = medianHrStd > 0
        ? (medianHrStd * 1.10).clamp(1.2, 3.0)
        : 1.5;

    // Deep Sleep: lowest HR near nocturnal nadir (p10 + 3.5 bpm) + steady parasympathetic quiescence
    if (epochMeanHr <= (baselineRestingHr + 3.5) &&
        epochHrRange <= 5.0 &&
        epochHrStd <= steadyStdThreshold) {
      return SleepStage.deep;
    }

    // REM Sleep: higher variable HR & autonomic bursts above nadir without waking tachycardia
    if (epochMeanHr > (baselineRestingHr + 2.0) &&
        epochMeanHr <= (baselineRestingHr + 15.0) &&
        (epochHrStd >= remStdThreshold || epochHrRange >= 5.0)) {
      return SleepStage.rem;
    }

    return SleepStage.light;
  }

  /// Temporal continuity smoothing across the hypnogram (Sliding 3-epoch window).
  /// In human sleep architecture, sleep stages typically persist in sustained bouts of several minutes.
  /// Isolated 30-second epoch flips between identical surrounding stages are usually PPG noise artifacts,
  /// unless accompanied by verifiable motor activity (arousal) or tachycardia.
  static List<SleepEpoch> smoothEpochs(List<SleepEpoch> epochs) {
    if (epochs.length < 3) return epochs;

    final smoothed = List<SleepEpoch>.from(epochs);

    for (int i = 1; i < epochs.length - 1; i++) {
      final prev = epochs[i - 1].stage;
      final curr = epochs[i].stage;
      final next = epochs[i + 1].stage;

      // If previous and next epochs have the same stage, but current is an isolated flip:
      if (prev == next && curr != prev) {
        // True motor arousal or heart rate spike is preserved as Wake
        final isTrueWake = curr == SleepStage.wake &&
            (epochs[i].movementIndex >= 0.06 || epochs[i].meanHr >= 80);

        if (!isTrueWake) {
          smoothed[i] = epochs[i].copyWith(stage: prev);
        }
      }
    }

    return smoothed;
  }
}
