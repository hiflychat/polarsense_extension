import 'package:flutter/material.dart';
import '../../features/sedentary/sedentary_engine.dart';
import '../theme/app_theme.dart';

class SedentaryProgressBar extends StatelessWidget {
  final SedentaryStatus status;
  final VoidCallback onReset;

  const SedentaryProgressBar({
    super.key,
    required this.status,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final isAlerting = status.progressToAlert >= 1.0;
    final progressColor = isAlerting
        ? AppTheme.recoveryLow
        : (status.progressToAlert > 0.75
            ? AppTheme.recoveryModerate
            : AppTheme.polarCyan);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.airline_seat_recline_normal,
                      color: progressColor,
                      size: 26,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Sedentary Monitor',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                _buildStateChip(),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${status.sedentaryMinutes}',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    color: progressColor,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '/ ${status.alertThresholdMinutes} min',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white60,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Manual Reset',
                  onPressed: onReset,
                  icon: const Icon(Icons.refresh, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: status.progressToAlert,
                minHeight: 10,
                backgroundColor: AppTheme.darkBorder,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            if (status.activeWalkingSeconds > 0) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Active Walking Reset',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  Text(
                    '${status.activeWalkingSeconds} / 90s',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.recoveryGood,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: status.walkingResetProgress,
                  minHeight: 6,
                  backgroundColor: AppTheme.darkBorder,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.recoveryGood),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              isAlerting
                  ? '⚠️ Stand up! You have been sitting for ${status.sedentaryMinutes} minutes.'
                  : 'Walk continuously for 90 seconds (VMU ≥ 0.15g) to reset the sedentary timer.',
              style: TextStyle(
                fontSize: 12,
                color: isAlerting ? AppTheme.recoveryLow : Colors.white54,
                fontWeight: isAlerting ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateChip() {
    String label;
    Color color;

    switch (status.state) {
      case PostureState.sedentary:
        label = 'Stationary';
        color = Colors.blueGrey;
        break;
      case PostureState.intermediate:
        label = 'Moving (Arm)';
        color = Colors.amber;
        break;
      case PostureState.activeWalking:
        label = 'Walking';
        color = AppTheme.recoveryGood;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
