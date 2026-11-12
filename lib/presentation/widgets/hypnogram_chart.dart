import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/database/models/sleep_record.dart';
import '../../core/localization/app_strings.dart';
import '../theme/app_theme.dart';

class HypnogramChart extends ConsumerWidget {
  final List<SleepEpoch> epochs;

  const HypnogramChart({
    super.key,
    required this.epochs,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);

    if (epochs.length < 2) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.darkBorder),
        ),
        child: Text(
          epochs.isEmpty ? strings.noEpochData : strings.recordingNeed2Epochs,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < epochs.length; i++) {
      final epoch = epochs[i];
      double y;
      switch (epoch.stage) {
        case SleepStage.wake:
          y = 3.0;
          break;
        case SleepStage.rem:
          y = 2.0;
          break;
        case SleepStage.light:
          y = 1.0;
          break;
        case SleepStage.deep:
          y = 0.0;
          break;
      }
      spots.add(FlSpot(i.toDouble(), y));
    }

    final timeFormat = DateFormat('HH:mm');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    strings.sleepHypnogram,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                _buildLegend(strings),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 170,
              child: LineChart(
                LineChartData(
                  minY: -0.2,
                  maxY: 3.2,
                  minX: 0,
                  maxX: (epochs.length - 1).toDouble().clamp(1.0, double.infinity),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1.0,
                    getDrawingHorizontalLine: (value) => const FlLine(
                      color: AppTheme.darkBorder,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        interval: 1.0,
                        getTitlesWidget: (value, meta) {
                          String label;
                          Color color;
                          switch (value.toInt()) {
                            case 3:
                              label = strings.stageWakeAxis;
                              color = AppTheme.wakeColor;
                              break;
                            case 2:
                              label = strings.stageRemAxis;
                              color = AppTheme.remColor;
                              break;
                            case 1:
                              label = strings.stageLightAxis;
                              color = AppTheme.lightColor;
                              break;
                            case 0:
                              label = strings.stageDeepAxis;
                              color = AppTheme.deepColor;
                              break;
                            default:
                              return const SizedBox.shrink();
                          }
                          return Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: (epochs.length / 4).clamp(1.0, double.infinity),
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt().clamp(0, epochs.length - 1);
                          final time = epochs[idx].timestamp;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              timeFormat.format(time),
                              style: const TextStyle(color: Colors.white38, fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: false,
                      isStepLineChart: true,
                      barWidth: 2.2,
                      color: AppTheme.polarCyan,
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.wakeColor.withOpacity(0.3),
                            AppTheme.remColor.withOpacity(0.2),
                            AppTheme.lightColor.withOpacity(0.15),
                            AppTheme.deepColor.withOpacity(0.4),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.darkBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        strings.hypnogramLegendTitle,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                        ),
                      ),
                      _LegendDot(color: AppTheme.wakeColor, label: strings.hypnogramLegendWake),
                      _LegendDot(color: AppTheme.remColor, label: strings.hypnogramLegendRem),
                      _LegendDot(color: AppTheme.lightColor, label: strings.hypnogramLegendLight),
                      _LegendDot(color: AppTheme.deepColor, label: strings.hypnogramLegendDeep),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.hypnogramAxisNote,
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(AppStrings strings) {
    return Row(
      children: [
        _LegendDot(color: AppTheme.wakeColor, label: strings.stageWakeAxis),
        const SizedBox(width: 6),
        _LegendDot(color: AppTheme.remColor, label: strings.stageRemAxis),
        const SizedBox(width: 6),
        _LegendDot(color: AppTheme.lightColor, label: strings.stageLightAxis),
        const SizedBox(width: 6),
        _LegendDot(color: AppTheme.deepColor, label: strings.stageDeepAxis),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
