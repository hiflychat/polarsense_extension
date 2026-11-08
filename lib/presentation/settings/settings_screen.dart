import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/background/background_service.dart';
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
    final sedentaryStatus = ref.watch(sedentaryStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Ecosystem'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Sedentary Alert Settings
          _buildSectionHeader('Sedentary Reminder'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Stationary Alert Threshold',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Trigger notification and vibration when arm movement VMU remains below 0.04g.',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [30, 45, 60, 90].map((minutes) {
                      final isSelected = sedentaryStatus.alertThresholdMinutes == minutes;
                      return ChoiceChip(
                        label: Text('$minutes min'),
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
                  const Row(
                    children: [
                      Icon(Icons.directions_walk, size: 18, color: AppTheme.recoveryGood),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Walking Reset Requirement: 90 seconds continuous active arm swing (VMU ≥ 0.15g).',
                          style: TextStyle(fontSize: 11, color: Colors.white60),
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
          _buildSectionHeader('Health Ecosystem Sync'),
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
                    title: Text(Platform.isIOS ? 'Apple HealthKit' : 'Google Health Connect'),
                    subtitle: const Text(
                      'Exports overnight sleep stages, RHR, and HRV (RMSSD).',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    trailing: OutlinedButton(
                      onPressed: () => _healthService.requestPermissions(),
                      child: const Text('Permissions'),
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
                      onPressed: _isSyncingAll ? null : _syncAllSessions,
                      icon: _isSyncingAll
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.sync, size: 18),
                      label: Text(_isSyncingAll ? 'Syncing...' : 'Sync All Sleep Sessions'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 3. Background Execution
          _buildSectionHeader('Background Execution'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.stay_current_portrait, color: AppTheme.polarCyan),
              title: const Text('Keep Sensor Connection in Background'),
              subtitle: Text(
                Platform.isAndroid
                    ? 'Maintains an ongoing foreground service with persistent notification.'
                    : 'Uses CoreBluetooth background central mode for overnight sleep recording.',
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
          _buildSectionHeader('About PolarSense Extension'),
          const Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Polar Verity Sense Extension', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Version 1.0.0 • Polar BLE SDK 7.11.0', style: TextStyle(fontSize: 12, color: Colors.white54)),
                  SizedBox(height: 8),
                  Text(
                    'Extends Polar optical heart rate sensors with 26 Hz accelerometer posture analysis, overnight sleep staging heuristic, and HRV recovery evaluation.',
                    style: TextStyle(fontSize: 12, color: Colors.white38),
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

  Future<void> _syncAllSessions() async {
    setState(() => _isSyncingAll = true);
    final count = await _healthService.syncAllUnsyncedSessions();
    setState(() => _isSyncingAll = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synced $count sleep session(s) successfully.'),
          backgroundColor: AppTheme.recoveryGood,
        ),
      );
    }
  }
}
