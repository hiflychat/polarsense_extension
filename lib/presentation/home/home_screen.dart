import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ble/polar_ble_manager.dart';
import '../../core/database/models/sleep_record.dart';
import '../../core/localization/app_strings.dart';
import '../../features/sedentary/sedentary_notifier.dart';
import '../../features/sleep/sleep_engine.dart';
import '../../features/sleep/sleep_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';
import '../widgets/pulse_indicator.dart';
import '../widgets/recovery_gauge.dart';
import '../widgets/sedentary_progress_bar.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final bleManager = ref.watch(polarBleManagerProvider);
    final sleepState = ref.watch(sleepHistoryProvider);
    final liveSleep = ref.watch(liveSleepStatusProvider).valueOrNull;

    final isBleConnected = bleManager.connectionState == BleConnectionState.connected ||
        bleManager.connectionState == BleConnectionState.streaming;

    final latestSession = sleepState.sessions.isNotEmpty ? sleepState.sessions.first : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appTitle),
        actions: [
          StreamBuilder<int>(
            stream: bleManager.hrStream,
            initialData: bleManager.currentHr,
            builder: (context, snapshot) {
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: PulseIndicator(
                    hr: snapshot.data ?? bleManager.currentHr,
                    isConnected: isBleConnected,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(sleepHistoryProvider.notifier).loadSessions(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Sedentary Live Tracking (Granular rebuild scoped only to progress bar)
              Consumer(
                builder: (context, ref, _) {
                  final status = ref.watch(sedentaryStatusProvider);
                  return SedentaryProgressBar(
                    status: status,
                    onReset: () => ref.read(sedentaryStatusProvider.notifier).resetTimer(),
                  );
                },
              ),

              const SizedBox(height: 16),

              // 2. Active Sleep Tracking Banner (if active)
              if (liveSleep != null && liveSleep.isTracking)
                _buildActiveSleepBanner(context, ref, liveSleep, strings)
              else
                _buildStartSleepCard(context, ref, isBleConnected, strings),

              const SizedBox(height: 16),

              // 3. Last Night's Recovery Summary Card
              if (latestSession != null)
                _buildLatestRecoveryCard(context, latestSession, strings)
              else
                _buildEmptyRecoveryCard(strings),

              const SizedBox(height: 16),

              // 4. Biometric Quick Cards (Granular rebuild scoped only to metric cards)
              Consumer(
                builder: (context, ref, _) {
                  final status = ref.watch(sedentaryStatusProvider);
                  return Row(
                    children: [
                      Expanded(
                        child: MetricCard(
                          icon: Icons.timer,
                          iconColor: AppTheme.polarCyan,
                          title: strings.currentSitting,
                          value: status.formattedDuration,
                          unit: '',
                          subtitle: '${strings.limit}: ${status.alertThresholdMinutes} ${strings.min}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MetricCard(
                          icon: Icons.directions_walk,
                          iconColor: AppTheme.recoveryGood,
                          title: strings.walkingStreak,
                          value: '${status.activeWalkingSeconds}',
                          unit: strings.sec,
                          subtitle: strings.goal90s,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSleepBanner(
      BuildContext context, WidgetRef ref, LiveSleepStatus liveSleep, AppStrings strings) {
    final minutes = liveSleep.elapsed.inMinutes;
    final seconds = liveSleep.elapsed.inSeconds % 60;
    final stageName = _getLocalizedSleepStage(liveSleep.currentStage, strings);

    return Card(
      color: AppTheme.remColor.withOpacity(0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.remColor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.bedtime, color: AppTheme.remColor, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.sleepTrackingActive,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${strings.elapsed}: ${minutes}${strings.min} ${seconds}${strings.sec}  •  ${strings.stage}: $stageName',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.polarRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => ref.read(sleepHistoryProvider.notifier).stopTracking(),
              child: Text(strings.wakeUpAndSave),
            ),
          ],
        ),
      ),
    );
  }

  String _getLocalizedSleepStage(SleepStage stage, AppStrings strings) {
    switch (stage) {
      case SleepStage.wake:
        return strings.wake;
      case SleepStage.rem:
        return strings.rem;
      case SleepStage.light:
        return strings.light;
      case SleepStage.deep:
        return strings.deep;
    }
  }

  Widget _buildStartSleepCard(
      BuildContext context, WidgetRef ref, bool isBleConnected, AppStrings strings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.remColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.nightlight_round, color: AppTheme.remColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.trackOvernightSleep,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.syncOfflineSleepDesc,
                        style: const TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.help_outline, color: AppTheme.polarCyan, size: 20),
                  tooltip: strings.offlineGuideDialogTitle,
                  onPressed: () => _showOfflineGuideDialog(context, strings),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                // 1. Sync from Sense Memory (Primary Offline Button)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.polarCyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isBleConnected
                        ? () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(strings.readingDeviceExercises),
                                  ],
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );

                            final session = await ref.read(sleepHistoryProvider.notifier).syncOfflineSleep();
                            if (context.mounted) {
                              if (session != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(strings.offlineSyncSuccess),
                                    backgroundColor: AppTheme.recoveryGood,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(strings.noExercisesFound),
                                  ),
                                );
                              }
                            }
                          }
                        : null,
                    icon: const Icon(Icons.download_for_offline, size: 18),
                    label: Text(
                      isBleConnected ? strings.syncOfflineSleep : strings.connectBleFirst,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 2. Real-time Live Tracking Button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.remColor,
                    side: const BorderSide(color: AppTheme.remColor),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isBleConnected
                      ? () => ref.read(sleepHistoryProvider.notifier).startTracking()
                      : null,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(strings.liveTrackingMode, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showOfflineGuideDialog(BuildContext context, AppStrings strings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: Row(
          children: [
            const Icon(Icons.menu_book, color: AppTheme.polarCyan, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.offlineGuideDialogTitle,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.offlineGuideStep1, style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.white70)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.recoveryGood.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.recoveryGood.withOpacity(0.3)),
                ),
                child: Text(
                  strings.offlineGuideStep2,
                  style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.recoveryGood, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              Text(strings.offlineGuideStep3, style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.white70)),
              const SizedBox(height: 12),
              Text(strings.offlineGuideStep4, style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.polarCyan)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了 / Got it', style: TextStyle(color: AppTheme.polarCyan)),
          ),
        ],
      ),
    );
  }

  Widget _buildLatestRecoveryCard(
      BuildContext context, SleepSession session, AppStrings strings) {
    final hours = (session.durationMinutes / 60.0).toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  strings.lastNightRecovery,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                RecoveryGauge(
                  score: session.recoveryScore,
                  size: 130,
                  subtitle: '$hours ${strings.hrs}',
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMetricRow(
                        strings.restingHrLowest,
                        '${session.restingHr.round()} ${strings.bpm}',
                        Icons.favorite,
                        AppTheme.polarRed,
                      ),
                      const SizedBox(height: 10),
                      _buildMetricRow(
                        strings.hrvTitle,
                        '${session.avgRmssd.round()} ${strings.ms}',
                        Icons.insights,
                        AppTheme.polarCyan,
                      ),
                      const SizedBox(height: 10),
                      _buildMetricRow(
                        strings.deep,
                        '${session.deepPercentage.round()}%',
                        Icons.waves,
                        AppTheme.deepColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white60),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildEmptyRecoveryCard(AppStrings strings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.bedtime_outlined, size: 40, color: Colors.white.withOpacity(0.3)),
              const SizedBox(height: 12),
              Text(
                strings.noSleepRecorded,
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                strings.noSleepRecordedDesc,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
