import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ble/polar_ble_manager.dart';
import '../../core/localization/app_strings.dart';
import '../../features/sedentary/sedentary_notifier.dart';
import '../../features/sleep/sleep_session_controller.dart';
import '../theme/app_theme.dart';

/// Shared helper to run Verity Sense offline synchronization with a live progress bottom sheet
/// and structured error / diagnostic feedback.
Future<void> runOfflineSyncWithModal({
  required BuildContext context,
  required WidgetRef ref,
  required AppStrings strings,
}) async {
  final bleManager = ref.read(polarBleManagerProvider);
  if (bleManager.connectionState == BleConnectionState.disconnected &&
      !bleManager.isMockMode) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.pleaseConnectSenseFirst),
        backgroundColor: AppTheme.polarRed,
      ),
    );
    return;
  }

  String progressMessage = strings.preparingSyncChannel;
  StateSetter? modalSetState;

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
          modalSetState = setModalState;
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

  final result =
      await ref.read(sleepHistoryProvider.notifier).syncOfflineSleepDetailed(
    onProgress: (status) {
      progressMessage = status;
      modalSetState?.call(() {});
    },
  );

  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  if (!context.mounted) return;

  final session = result.session;
  if (session != null) {
    final prefix = result.syncedCount > 0
        ? strings.offlineSyncSuccess
        : strings.allExercisesAlreadySynced;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$prefix (${session.durationFormatted}, ${strings.lastNightRecovery}: ${session.recoveryScore})',
        ),
        backgroundColor: AppTheme.recoveryGood,
        duration: const Duration(seconds: 4),
      ),
    );
  } else {
    showOfflineSyncGuideOrErrorDialog(context, strings, result);
  }
}

void showOfflineSyncGuideOrErrorDialog(
  BuildContext context,
  AppStrings strings,
  OfflineSyncResult result,
) {
  final isZh = strings.isZh;
  final rawErr = result.errorMessage ?? '';
  final isBusy = rawErr.contains('SYSTEM_BUSY') || rawErr.contains('202');

  String headline;
  if (isBusy) {
    headline = isZh
        ? '手环正忙或仍处于独立录制/游泳模式 (SYSTEM_BUSY 202)。请将手环切换回【蓝灯心率模式】或重启手环后重试。'
        : 'Sensor returned SYSTEM_BUSY (202). Please switch Verity Sense to Blue LED sensor mode or restart the sensor and retry.';
  } else if (rawErr.isNotEmpty) {
    headline = isZh
        ? '读取手环离线数据时遇到通信错误：\n$rawErr'
        : 'Communication error while reading offline data:\n$rawErr';
  } else if (result.entriesFound > 0 && result.skippedTooShort > 0) {
    headline = isZh
        ? '在手环中检测到 ${result.entriesFound} 条记录，但有效采样时长不足 30 秒（过短无法完成睡眠分期）。'
        : 'Found ${result.entriesFound} recording(s) on Sense, but fewer than 30 seconds of samples were recorded.';
  } else {
    headline = strings.noExercisesFound;
  }

  final diagText = _formatDiagnostics(result.diagnostics);

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            rawErr.isNotEmpty ? Icons.error_outline : Icons.info_outline,
            color: rawErr.isNotEmpty ? AppTheme.polarRed : AppTheme.polarCyan,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              strings.offlineGuideDialogTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
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
              headline,
              style: TextStyle(
                fontSize: 13,
                color: rawErr.isNotEmpty ? Colors.orangeAccent : Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            _buildGuideStep(strings.offlineGuideStep1),
            const SizedBox(height: 8),
            _buildGuideStep(strings.offlineGuideStep2),
            const SizedBox(height: 8),
            _buildGuideStep(strings.offlineGuideStep3),
            const SizedBox(height: 8),
            _buildGuideStep(strings.offlineGuideStep4),
            if (diagText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                isZh ? '设备存储诊断详情：' : 'Device Storage Diagnostics:',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  diagText,
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Colors.white60,
                  ),
                ),
              ),
            ],
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

String _formatDiagnostics(Map<String, dynamic>? diag) {
  if (diag == null || diag.isEmpty) return '';
  final buf = StringBuffer();
  if (diag['diskFreeBytes'] != null && diag['diskTotalBytes'] != null) {
    final freeMb = ((diag['diskFreeBytes'] as num) / (1024 * 1024)).toStringAsFixed(2);
    final totalMb = ((diag['diskTotalBytes'] as num) / (1024 * 1024)).toStringAsFixed(2);
    buf.writeln('Disk: $freeMb MB free / $totalMb MB total');
  }
  buf.writeln(
    'Ready: fileTransfer=${diag['fileTransferReady']}, offlineRec=${diag['offlineRecordingReady']}',
  );
  final u0Paths = (diag['u0Paths'] as List?) ?? const [];
  buf.writeln('/U/0/ entries (${u0Paths.length}): ${u0Paths.take(12).join(', ')}');
  final offlineEntries = (diag['offlineEntries'] as List?) ?? const [];
  if (offlineEntries.isNotEmpty) {
    buf.writeln('OfflineRec entries: ${offlineEntries.join(', ')}');
  }
  final errors = (diag['errors'] as List?) ?? const [];
  if (errors.isNotEmpty) {
    buf.writeln('Errors: ${errors.join(' | ')}');
  }
  return buf.toString().trim();
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
