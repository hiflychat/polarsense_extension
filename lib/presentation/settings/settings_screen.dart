import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/background/background_service.dart';
import '../../core/localization/app_strings.dart';
import '../../features/health_sync/health_export_service.dart';
import '../../features/sedentary/sedentary_notifier.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final BackgroundService _backgroundService = BackgroundService();
  final HealthExportService _healthService = HealthExportService();

  bool _isBackgroundActive = false;
  bool _isSyncingAll = false;

  @override
  void initState() {
    super.initState();
    _isBackgroundActive = _backgroundService.isRunning;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final currentLanguage = ref.watch(appLanguageProvider);
    final alertThresholdMinutes = ref.watch(
      sedentaryStatusProvider.select((s) => s.alertThresholdMinutes),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.settingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 0. Language Selector (中英双语设置)
          _buildSectionHeader(strings.languageSetting),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.language, color: AppTheme.polarCyan, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        strings.languageSetting,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ChoiceChip(
                        label: Text(strings.simplifiedChinese),
                        selected: currentLanguage == AppLanguage.zh,
                        selectedColor: AppTheme.polarCyan.withOpacity(0.25),
                        labelStyle: TextStyle(
                          color: currentLanguage == AppLanguage.zh ? AppTheme.polarCyan : Colors.white70,
                          fontWeight: currentLanguage == AppLanguage.zh ? FontWeight.bold : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: currentLanguage == AppLanguage.zh ? AppTheme.polarCyan : AppTheme.darkBorder,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            ref.read(appLanguageProvider.notifier).setLanguage(AppLanguage.zh);
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      ChoiceChip(
                        label: Text(strings.english),
                        selected: currentLanguage == AppLanguage.en,
                        selectedColor: AppTheme.polarCyan.withOpacity(0.25),
                        labelStyle: TextStyle(
                          color: currentLanguage == AppLanguage.en ? AppTheme.polarCyan : Colors.white70,
                          fontWeight: currentLanguage == AppLanguage.en ? FontWeight.bold : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: currentLanguage == AppLanguage.en ? AppTheme.polarCyan : AppTheme.darkBorder,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            ref.read(appLanguageProvider.notifier).setLanguage(AppLanguage.en);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 1. Sedentary Alert Settings
          _buildSectionHeader(strings.sedentaryTracker),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.sedentaryAlertInterval,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.sedentaryAlertDesc,
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [30, 45, 60, 90].map((minutes) {
                      final isSelected = alertThresholdMinutes == minutes;
                      return ChoiceChip(
                        label: Text('$minutes ${strings.min}'),
                        selected: isSelected,
                        selectedColor: AppTheme.polarCyan.withOpacity(0.25),
                        labelStyle: TextStyle(
                          color: isSelected ? AppTheme.polarCyan : Colors.white70,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? AppTheme.polarCyan : AppTheme.darkBorder,
                        ),
                        onSelected: (_) {
                          ref.read(sedentaryStatusProvider.notifier).setThreshold(minutes);
                        },
                      );
                    }).toList(),
                  ),
                  const Divider(color: AppTheme.darkBorder, height: 24),
                  Row(
                    children: [
                      const Icon(Icons.directions_walk, size: 18, color: AppTheme.recoveryGood),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.walkingResetTip,
                          style: const TextStyle(fontSize: 11, color: Colors.white60),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 2. HealthKit / Health Connect Sync
          _buildSectionHeader(strings.healthPermissions),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Colors.white12,
                      child: Icon(Icons.favorite, color: AppTheme.polarRed),
                    ),
                    title: Text(
                      Platform.isIOS
                          ? (strings.isZh ? 'Apple HealthKit (苹果健康)' : 'Apple HealthKit')
                          : (strings.isZh ? 'Google Health Connect (安卓健康中心)' : 'Google Health Connect'),
                    ),
                    subtitle: Text(
                      strings.healthPermissionsDesc,
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    trailing: OutlinedButton(
                      onPressed: () => _healthService.requestPermissions(),
                      child: Text(strings.requestAuth),
                    ),
                  ),
                  const Divider(color: AppTheme.darkBorder),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.polarCyan,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: _isSyncingAll ? null : () => _syncAllSessions(strings),
                      icon: _isSyncingAll
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.sync, size: 18),
                      label: Text(strings.syncAllSessions),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 3. Background Execution
          _buildSectionHeader(strings.backgroundExecution),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.stay_current_portrait, color: AppTheme.polarCyan),
              title: Text(strings.backgroundExecution),
              subtitle: Text(
                strings.backgroundDesc,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
              value: _isBackgroundActive,
              activeColor: AppTheme.polarCyan,
              onChanged: (val) async {
                if (val) {
                  await _backgroundService.startService();
                } else {
                  await _backgroundService.stopService();
                }
                setState(() => _isBackgroundActive = _backgroundService.isRunning);
              },
            ),
          ),

          const SizedBox(height: 20),

          // 4. About & SDK
          _buildSectionHeader(strings.aboutPolarSense),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.aboutAppName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${strings.version} 1.0.17 • Polar BLE SDK 7.12.0', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  const SizedBox(height: 8),
                  Text(
                    strings.hardwareSimulatorDesc,
                    style: const TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white54,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Future<void> _syncAllSessions(AppStrings strings) async {
    setState(() => _isSyncingAll = true);
    final count = await _healthService.syncAllUnsyncedSessions();
    setState(() => _isSyncingAll = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${strings.sessionsSynced}: $count'),
          backgroundColor: AppTheme.recoveryGood,
        ),
      );
    }
  }
}
