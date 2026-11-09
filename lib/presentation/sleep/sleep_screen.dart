import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/database/models/sleep_record.dart';
import '../../core/localization/app_strings.dart';
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
  bool _isOfflineSyncing = false;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final sleepState = ref.watch(sleepHistoryProvider);
    final selectedSession = sleepState.selectedSession;
    final epochs = sleepState.selectedEpochs;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.sleepRecoveryTitle),
        actions: [
          // 1. Sync from Sense Memory Action Button
          IconButton(
            tooltip: strings.syncOfflineSleep,
            icon: _isOfflineSyncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.polarCyan),
                  )
                : const Icon(Icons.download_for_offline, color: AppTheme.polarCyan),
            onPressed: _isOfflineSyncing ? null : () => _handleOfflineSync(strings),
          ),
          if (selectedSession != null)
            IconButton(
              tooltip: strings.exportTooltip,
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
              onPressed: _isSyncing ? null : () => _handleSync(selectedSession, strings),
            ),
        ],
      ),
      body: sleepState.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.polarCyan))
          : (sleepState.sessions.isEmpty
              ? _buildEmptyState(strings)
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
                        _buildRecoveryHeader(selectedSession, strings),

                        const SizedBox(height: 16),

                        // 3. Sleep Hypnogram
                        HypnogramChart(epochs: epochs),

                        const SizedBox(height: 16),

                        // 4. Stage Breakdown Bar
                        _buildStageProportionCard(selectedSession, strings),

                        const SizedBox(height: 16),

                        // 5. Biometric Grid
                        _buildMetricsGrid(selectedSession, strings),
                      ],
                    ],
                  ),
                )),
    );
  }

  Widget _buildEmptyState(AppStrings strings) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bedtime_outlined, size: 56, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              strings.noSleepEmpty,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              strings.noSleepEmptyDesc,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.polarCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isOfflineSyncing ? null : () => _handleOfflineSync(strings),
              icon: _isOfflineSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.download_for_offline, size: 20),
              label: Text(
                strings.syncOfflineSleep,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.polarCyan,
                side: const BorderSide(color: AppTheme.polarCyan),
              ),
              onPressed: () async {
                final session = await ref.read(sleepHistoryProvider.notifier).generateMockOfflineSleep();
                if (mounted && session != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(strings.offlineSyncSuccess),
                      backgroundColor: AppTheme.recoveryGood,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.science, size: 18),
              label: Text(strings.generateMockOffline),
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

  Widget _buildRecoveryHeader(SleepSession session, AppStrings strings) {
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
                      _buildScoreFactorRow(strings.durationFactor, '${breakdown.durationScore.round()}/100'),
                      const SizedBox(height: 4),
                      _buildScoreFactorRow(strings.stageRatioFactor, '${breakdown.stageRatioScore.round()}/100'),
                      const SizedBox(height: 4),
                      _buildScoreFactorRow(strings.hrvFactor, '${breakdown.hrvScore.round()}/100'),
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

  Widget _buildStageProportionCard(SleepSession session, AppStrings strings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.stageDistribution,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
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
                        flex: (session.deepPercentage * 10).round().clamp(1, 1000),
                        child: Container(color: AppTheme.deepColor),
                      ),
                    if (session.lightPercentage > 0)
                      Expanded(
                        flex: (session.lightPercentage * 10).round().clamp(1, 1000),
                        child: Container(color: AppTheme.lightColor),
                      ),
                    if (session.remPercentage > 0)
                      Expanded(
                        flex: (session.remPercentage * 10).round().clamp(1, 1000),
                        child: Container(color: AppTheme.remColor),
                      ),
                    if (session.wakePercentage > 0)
                      Expanded(
                        flex: (session.wakePercentage * 10).round().clamp(1, 1000),
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
                _buildStageStat(strings.deep, '${session.deepMinutes}${strings.min}', '${session.deepPercentage.round()}%', AppTheme.deepColor),
                _buildStageStat(strings.light, '${session.lightMinutes}${strings.min}', '${session.lightPercentage.round()}%', AppTheme.lightColor),
                _buildStageStat(strings.rem, '${session.remMinutes}${strings.min}', '${session.remPercentage.round()}%', AppTheme.remColor),
                _buildStageStat(strings.wake, '${session.wakeMinutes}${strings.min}', '${session.wakePercentage.round()}%', AppTheme.wakeColor),
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

  Widget _buildMetricsGrid(SleepSession session, AppStrings strings) {
    final hours = (session.durationMinutes / 60.0).toStringAsFixed(1);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: MetricCard(
                icon: Icons.hotel,
                iconColor: AppTheme.polarCyan,
                title: strings.totalSleep,
                value: hours,
                unit: strings.hrs,
                subtitle: '${session.durationMinutes} ${strings.min}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                icon: Icons.favorite,
                iconColor: AppTheme.polarRed,
                title: strings.restingHrLowest,
                value: '${session.restingHr.round()}',
                unit: strings.bpm,
                subtitle: strings.restingHrDesc,
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
                title: strings.hrvTitle,
                value: '${session.avgRmssd.round()}',
                unit: strings.ms,
                subtitle: strings.hrvDesc,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                icon: Icons.cloud_done,
                iconColor: session.syncedToHealth ? AppTheme.recoveryGood : Colors.white38,
                title: strings.healthSync,
                value: session.syncedToHealth ? strings.synced : strings.localOnly,
                unit: '',
                subtitle: 'HealthKit / Health Connect',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _handleSync(SleepSession session, AppStrings strings) async {
    setState(() => _isSyncing = true);
    final ok = await _healthExportService.exportSleepSession(session);
    setState(() => _isSyncing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? strings.syncSuccess : strings.syncFail),
          backgroundColor: ok ? AppTheme.recoveryGood : AppTheme.polarRed,
        ),
      );
      ref.read(sleepHistoryProvider.notifier).loadSessions();
    }
  }

  Future<void> _handleOfflineSync(AppStrings strings) async {
    setState(() => _isOfflineSyncing = true);

    String progressMessage = strings.readingDeviceExercisesStep;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppTheme.polarCyan,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    strings.syncOfflineSleep,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    progressMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    final session = await ref.read(sleepHistoryProvider.notifier).syncOfflineSleep();

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    setState(() => _isOfflineSyncing = false);

    if (mounted) {
      if (session != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${strings.offlineSyncSuccess} (${session.durationFormatted}, ${strings.lastNightRecovery}: ${session.recoveryScore})',
            ),
            backgroundColor: AppTheme.recoveryGood,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        _showOfflineGuideDialog(strings);
      }
    }
  }

  void _showOfflineGuideDialog(AppStrings strings) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: AppTheme.polarCyan, size: 22),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.noExercisesFound,
                style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              _buildGuideStep(strings.offlineGuideStep1),
              const SizedBox(height: 8),
              _buildGuideStep(strings.offlineGuideStep2),
              const SizedBox(height: 8),
              _buildGuideStep(strings.offlineGuideStep3),
              const SizedBox(height: 8),
              _buildGuideStep(strings.offlineGuideStep4),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: AppTheme.polarCyan)),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideStep(String step) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.darkBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Text(
        step,
        style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
      ),
    );
  }
}
