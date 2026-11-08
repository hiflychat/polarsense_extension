import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/database/models/sleep_record.dart';
import '../../features/health_sync/health_export_service.dart';
import '../../features/sleep/recovery_score_calculator.dart';
import '../../features/sleep/sleep_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/hypnogram_chart.dart';
import '../widgets/metric_card.dart';
import '../widgets/recovery_gauge.dart';

class SleepScreen extends ConsumerStatefulWidget {
  const SleepScreen({super.key});

  @override
  ConsumerState<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends ConsumerState<SleepScreen> {
  final HealthExportService _healthExportService = HealthExportService();
  bool _isSyncing = false;

  @override
  Widget build(BuildContext context) {
    final sleepState = ref.watch(sleepHistoryProvider);
    final selectedSession = sleepState.selectedSession;
    final epochs = sleepState.selectedEpochs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sleep & Recovery'),
        actions: [
          if (selectedSession != null)
            IconButton(
              tooltip: 'Export to HealthKit / Health Connect',
              icon: _isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.polarCyan),
                    )
                  : Icon(
                      selectedSession.syncedToHealth ? Icons.check_circle : Icons.upload_file,
                      color: selectedSession.syncedToHealth
                          ? AppTheme.recoveryGood
                          : AppTheme.polarCyan,
                    ),
              onPressed: _isSyncing ? null : () => _handleSync(selectedSession),
            ),
        ],
      ),
      body: sleepState.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.polarCyan))
          : (sleepState.sessions.isEmpty
              ? _buildEmptyState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Session Picker (Horizontal Date Pills)
                      _buildSessionPicker(sleepState.sessions, selectedSession),

                      const SizedBox(height: 16),

                      if (selectedSession != null) ...[
                        // 2. Recovery Gauge & Breakdown
                        _buildRecoveryHeader(selectedSession),

                        const SizedBox(height: 16),

                        // 3. Sleep Hypnogram
                        HypnogramChart(epochs: epochs),

                        const SizedBox(height: 16),

                        // 4. Stage Breakdown Bar
                        _buildStageProportionCard(selectedSession),

                        const SizedBox(height: 16),

                        // 5. Biometric Grid
                        _buildMetricsGrid(selectedSession),
                      ],
                    ],
                  ),
                )),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bedtime_outlined, size: 56, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text(
              'No Sleep Sessions Recorded',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect your Polar Verity Sense and tap "Start Sleep Session" on the Home tab to record your overnight sleep stages.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionPicker(List<SleepSession> sessions, SleepSession? selected) {
    final dayFormat = DateFormat('EEE, MMM d');

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sessions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final s = sessions[index];
          final isSelected = selected?.id == s.id;

          return ChoiceChip(
            label: Text(dayFormat.format(s.startTime)),
            selected: isSelected,
            selectedColor: AppTheme.polarCyan.withOpacity(0.25),
            labelStyle: TextStyle(
              color: isSelected ? AppTheme.polarCyan : Colors.white70,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
            side: BorderSide(
              color: isSelected ? AppTheme.polarCyan : AppTheme.darkBorder,
            ),
            onSelected: (_) => ref.read(sleepHistoryProvider.notifier).selectSession(s),
          );
        },
      ),
    );
  }

  Widget _buildRecoveryHeader(SleepSession session) {
    final breakdown = RecoveryScoreCalculator.calculate(
      durationMinutes: session.durationMinutes,
      deepMinutes: session.deepMinutes,
      remMinutes: session.remMinutes,
      nightRmssd: session.avgRmssd,
      baseline14DayRmssd: 42.0,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                RecoveryGauge(score: session.recoveryScore, size: 140),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        breakdown.statusDescription,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.getRecoveryColor(session.recoveryScore),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildScoreFactorRow('Duration (30%)', '${breakdown.durationScore.round()}/100'),
                      const SizedBox(height: 4),
                      _buildScoreFactorRow('Deep+REM (30%)', '${breakdown.stageRatioScore.round()}/100'),
                      const SizedBox(height: 4),
                      _buildScoreFactorRow('HRV Index (40%)', '${breakdown.hrvScore.round()}/100'),
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

  Widget _buildScoreFactorRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }

  Widget _buildStageProportionCard(SleepSession session) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Stage Distribution',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 14),
            // Multi-segment horizontal bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    if (session.deepPercentage > 0)
                      Expanded(
                        flex: (session.deepPercentage * 10).round(),
                        child: Container(color: AppTheme.deepColor),
                      ),
                    if (session.lightPercentage > 0)
                      Expanded(
                        flex: (session.lightPercentage * 10).round(),
                        child: Container(color: AppTheme.lightColor),
                      ),
                    if (session.remPercentage > 0)
                      Expanded(
                        flex: (session.remPercentage * 10).round(),
                        child: Container(color: AppTheme.remColor),
                      ),
                    if (session.wakePercentage > 0)
                      Expanded(
                        flex: (session.wakePercentage * 10).round(),
                        child: Container(color: AppTheme.wakeColor),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStageStat('Deep', '${session.deepMinutes}m', '${session.deepPercentage.round()}%', AppTheme.deepColor),
                _buildStageStat('Light', '${session.lightMinutes}m', '${session.lightPercentage.round()}%', AppTheme.lightColor),
                _buildStageStat('REM', '${session.remMinutes}m', '${session.remPercentage.round()}%', AppTheme.remColor),
                _buildStageStat('Wake', '${session.wakeMinutes}m', '${session.wakePercentage.round()}%', AppTheme.wakeColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStageStat(String stage, String duration, String percent, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(stage, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        const SizedBox(height: 4),
        Text(duration, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(percent, style: const TextStyle(fontSize: 10, color: Colors.white38)),
      ],
    );
  }

  Widget _buildMetricsGrid(SleepSession session) {
    final hours = (session.durationMinutes / 60.0).toStringAsFixed(1);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: MetricCard(
                icon: Icons.hotel,
                iconColor: AppTheme.polarCyan,
                title: 'Total Sleep',
                value: hours,
                unit: 'hrs',
                subtitle: '${session.durationMinutes} minutes in bed',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                icon: Icons.favorite,
                iconColor: AppTheme.polarRed,
                title: 'Resting HR',
                value: '${session.restingHr.round()}',
                unit: 'bpm',
                subtitle: 'Overnight lowest 10%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                icon: Icons.show_chart,
                iconColor: AppTheme.recoveryGood,
                title: 'HRV (RMSSD)',
                value: '${session.avgRmssd.round()}',
                unit: 'ms',
                subtitle: 'Autonomic recovery',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                icon: Icons.cloud_done,
                iconColor: session.syncedToHealth ? AppTheme.recoveryGood : Colors.white38,
                title: 'Health Sync',
                value: session.syncedToHealth ? 'Synced' : 'Local',
                unit: '',
                subtitle: 'Apple Health / Health Connect',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _handleSync(SleepSession session) async {
    setState(() => _isSyncing = true);
    final ok = await _healthExportService.exportSleepSession(session);
    setState(() => _isSyncing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Successfully synced session to Health ecosystem!'
                : 'Could not sync. Ensure Health permissions are granted.',
          ),
          backgroundColor: ok ? AppTheme.recoveryGood : AppTheme.polarRed,
        ),
      );
      ref.read(sleepHistoryProvider.notifier).loadSessions();
    }
  }
}
