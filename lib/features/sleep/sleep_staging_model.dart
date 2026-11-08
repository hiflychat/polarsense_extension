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
}
