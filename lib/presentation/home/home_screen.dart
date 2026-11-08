import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ble/polar_ble_manager.dart';
import '../../features/sedentary/sedentary_notifier.dart';
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
    final bleManager = ref.watch(polarBleManagerProvider);
    final sedentaryStatus = ref.watch(sedentaryStatusProvider);
    final sleepState = ref.watch(sleepHistoryProvider);
    final liveSleep = ref.watch(liveSleepStatusProvider).valueOrNull;

    final isBleConnected = bleManager.connectionState == BleConnectionState.connected ||
        bleManager.connectionState == BleConnectionState.streaming;

    final latestSession = sleepState.sessions.isNotEmpty ? sleepState.sessions.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PolarSense'),
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
              // 1. Sedentary Live Tracking
              SedentaryProgressBar(
                status: sedentaryStatus,
                onReset: () => ref.read(sedentaryStatusProvider.notifier).resetTimer(),
              ),

              const SizedBox(height: 16),

              // 2. Active Sleep Tracking Banner (if active)
              if (liveSleep != null && liveSleep.isTracking)
                _buildActiveSleepBanner(context, ref, liveSleep)
              else
                _buildStartSleepCard(context, ref, isBleConnected),

              const SizedBox(height: 16),

              // 3. Last Night's Recovery Summary Card
              if (latestSession != null)
                _buildLatestRecoveryCard(context, latestSession)
              else
                _buildEmptyRecoveryCard(),

              const SizedBox(height: 16),

              // 4. Biometric Quick Cards
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      icon: Icons.timer,
                      iconColor: AppTheme.polarCyan,
                      title: 'Current Sitting',
                      value: '${sedentaryStatus.sedentaryMinutes}',
                      unit: 'min',
                      subtitle: 'Limit: ${sedentaryStatus.alertThresholdMinutes} min',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricCard(
                      icon: Icons.directions_walk,
                      iconColor: AppTheme.recoveryGood,
                      title: 'Walking Streak',
                      value: '${sedentaryStatus.activeWalkingSeconds}',
                      unit: 'sec',
                      subtitle: 'Goal: 90 sec reset',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSleepBanner(
      BuildContext context, WidgetRef ref, dynamic liveSleep) {
    final minutes = liveSleep.elapsed.inMinutes;
    final seconds = liveSleep.elapsed.inSeconds % 60;

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
                  const Text(
                    'Sleep Session Active',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Elapsed: ${minutes}m ${seconds}s  •  Stage: ${liveSleep.currentStage.name}',
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
              child: const Text('Wake Up'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartSleepCard(BuildContext context, WidgetRef ref, bool isBleConnected) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.remColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.nightlight_round, color: AppTheme.remColor, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Track Overnight Sleep',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Records PPI, RMSSD, and 30s epochs',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.polarCyan.withOpacity(0.2),
                foregroundColor: AppTheme.polarCyan,
              ),
              onPressed: isBleConnected
                  ? () => ref.read(sleepHistoryProvider.notifier).startTracking()
                  : null,
              child: Text(isBleConnected ? 'Start' : 'Connect BLE'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestRecoveryCard(BuildContext context, dynamic session) {
    final hours = (session.durationMinutes / 60.0).toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Last Night Recovery',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                RecoveryGauge(
                  score: session.recoveryScore,
                  size: 130,
                  subtitle: '$hours hrs sleep',
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMetricRow(
                        'Resting HR',
                        '${session.restingHr.round()} bpm',
                        Icons.favorite,
                        AppTheme.polarRed,
                      ),
                      const SizedBox(height: 10),
                      _buildMetricRow(
                        'Night HRV',
                        '${session.avgRmssd.round()} ms',
                        Icons.insights,
                        AppTheme.polarCyan,
                      ),
                      const SizedBox(height: 10),
                      _buildMetricRow(
                        'Deep Sleep',
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
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white60),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildEmptyRecoveryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.bedtime_outlined, size: 40, color: Colors.white.withOpacity(0.3)),
              const SizedBox(height: 12),
              const Text(
                'No sleep session recorded yet',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Wear your Polar Verity Sense to bed and tap "Start" to record sleep stages & recovery.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
