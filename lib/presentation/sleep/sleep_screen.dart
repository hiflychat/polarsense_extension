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
import '../widgets/offline_sync_helper.dart';
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
          if (selectedSession != null) ...[
            IconButton(
              tooltip: strings.deleteSessionTitle,
              icon: const Icon(Icons.delete_outline, color: Colors.white54),
              onPressed: () => _confirmDeleteSession(selectedSession, strings),
            ),
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
                      _buildSessionPicker(sleepState.sessions, selectedSession, strings),

                      const SizedBox(height: 16),

                      if (selectedSession != null) ...[
                        // 2. Recovery Gauge & Breakdown
                        _buildRecoveryHeader(
                          selectedSession,
                          sleepState.baseline14DayRmssd,
                          strings,
                        ),

                        const SizedBox(height: 12),

                        // Data Source & Mode Explanation Banner
                        _buildDataSourceBanner(selectedSession, strings),

                        const SizedBox(height: 16),

                        // 3. Sleep Hypnogram
                        HypnogramChart(epochs: epochs),

                        const SizedBox(height: 16),

                        // 4. Stage Breakdown Bar
                        _buildStageProportionCard(selectedSession, strings),

                        const SizedBox(height: 16),

                        // 5. Biometric Grid
                        _buildMetricsGrid(selectedSession, strings),

                        const SizedBox(height: 16),

                        // 6. Biometric Terminology Legend (图注)
                        _buildGlossaryCard(strings),
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

  Widget _buildSessionPicker(
    List<SleepSession> sessions,
    SleepSession? selected,
    AppStrings strings,
  ) {
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
          final labelText = strings.isZh
              ? _formatChineseDate(s.startTime)
              : dayFormat.format(s.startTime);

          return ChoiceChip(
            label: Text(labelText),
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

  String _formatChineseDate(DateTime dt) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final wd = weekdays[(dt.weekday - 1).clamp(0, 6)];
    return '${dt.month}月${dt.day}日 $wd';
  }

  Widget _buildRecoveryHeader(
    SleepSession session,
    double baseline14DayRmssd,
    AppStrings strings,
  ) {
    final hasHrv = session.hasHrvData;
    final breakdown = RecoveryScoreCalculator.calculate(
      durationMinutes: session.effectiveSleepMinutes,
      deepMinutes: session.deepMinutes,
      remMinutes: session.remMinutes,
      nightRmssd: session.avgRmssd,
      baseline14DayRmssd: baseline14DayRmssd,
      hasHrvData: hasHrv,
    );

    final durationWeight = hasHrv ? 30 : 50;
    final stageWeight = hasHrv ? 30 : 50;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                RecoveryGauge(
                  score: session.recoveryScore,
                  size: 140,
                  subtitle: session.formattedDuration(isZh: strings.isZh),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.recoveryStatusLabel(session.recoveryScore),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.getRecoveryColor(session.recoveryScore),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildScoreFactorRow(
                        strings.durationFactorWeighted(durationWeight),
                        '${breakdown.durationScore.round()}/100',
                      ),
                      const SizedBox(height: 4),
                      _buildScoreFactorRow(
                        strings.stageRatioFactorWeighted(stageWeight),
                        '${breakdown.stageRatioScore.round()}/100',
                      ),
                      const SizedBox(height: 4),
                      _buildScoreFactorRow(
                        hasHrv ? strings.hrvFactor : strings.hrvFactorUnavailable,
                        hasHrv
                            ? '${breakdown.hrvScore.round()}/100'
                            : strings.hrvUnavailableShort,
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

  Widget _buildDataSourceBanner(SleepSession session, AppStrings strings) {
    final isHrOnly = session.isHrOnlyOffline;
    final badgeColor = isHrOnly ? Colors.amber : AppTheme.polarCyan;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isHrOnly ? Icons.info_outline : Icons.verified_outlined,
                size: 16,
                color: badgeColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.dataSourceLabel(session.dataSource),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          if (isHrOnly) ...[
            const SizedBox(height: 6),
            Text(
              strings.hrOnlyModeNotice,
              style: const TextStyle(fontSize: 11, color: Colors.white70, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScoreFactorRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
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
    final hasHrv = session.hasHrvData;

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
                subtitle: strings.actualSleepEfficiencySub(
                  session.actualSleepMinutes,
                  session.sleepEfficiency,
                ),
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
                iconColor: hasHrv ? AppTheme.recoveryGood : Colors.amber,
                title: strings.hrvTitle,
                value: hasHrv ? '${session.avgRmssd.round()}' : strings.hrvUnavailableShort,
                unit: hasHrv ? strings.ms : '',
                subtitle: hasHrv ? strings.hrvDesc : strings.hrvUnavailableDesc,
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
                subtitle: strings.healthEcosystemSub,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGlossaryCard(AppStrings strings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_outlined, color: AppTheme.polarCyan, size: 18),
                const SizedBox(width: 8),
                Text(
                  strings.metricGlossaryTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...strings.glossaryItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.term,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.polarCyan,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.desc,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSession(SleepSession session, AppStrings strings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: Text(strings.deleteSessionTitle, style: const TextStyle(color: Colors.white)),
        content: Text(
          strings.deleteSessionConfirm,
          style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancel, style: const TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.deleteLabel, style: const TextStyle(color: AppTheme.polarRed)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(sleepHistoryProvider.notifier).deleteSession(session.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.sessionDeleted)),
        );
      }
    }
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
    try {
      await runOfflineSyncWithModal(
        context: context,
        ref: ref,
        strings: strings,
      );
    } finally {
      if (mounted) {
        setState(() => _isOfflineSyncing = false);
      }
    }
  }
}
