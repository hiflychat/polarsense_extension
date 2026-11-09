import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ble/polar_ble_manager.dart';
import '../../core/localization/app_strings.dart';
import '../../features/sedentary/sedentary_notifier.dart';
import '../../features/sleep/sleep_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/pulse_indicator.dart';

class DeviceScreen extends ConsumerStatefulWidget {
  const DeviceScreen({super.key});

  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  bool _mockWalking = false;
  Future<bool>? _permissionsFuture;

  @override
  void initState() {
    super.initState();
    _permissionsFuture = PolarBleManager.hasBlePermissions();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final bleManager = ref.watch(polarBleManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.sensorTitle),
        actions: [
          StreamBuilder<int>(
            stream: bleManager.hrStream,
            initialData: bleManager.currentHr,
            builder: (context, snapshot) {
              final hr = snapshot.data ?? bleManager.currentHr;
              final isConnected = bleManager.connectionState == BleConnectionState.connected ||
                  bleManager.connectionState == BleConnectionState.streaming;

              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: PulseIndicator(
                    hr: hr,
                    isConnected: isConnected,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<BleConnectionState>(
        stream: bleManager.stateStream,
        initialData: bleManager.connectionState,
        builder: (context, snapshot) {
          final state = snapshot.data ?? BleConnectionState.disconnected;
          final isConnected = state == BleConnectionState.connected ||
              state == BleConnectionState.streaming;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 0. Permission Warning Banner (if permissions not granted)
              FutureBuilder<bool>(
                future: _permissionsFuture,
                builder: (context, permSnapshot) {
                  if (permSnapshot.hasData && permSnapshot.data == false) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.amber.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.security, color: Colors.amber, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              strings.bluetoothPermissionPrompt,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            onPressed: () async {
                              await PolarBleManager.requestBlePermissions();
                              setState(() {
                                _permissionsFuture = PolarBleManager.hasBlePermissions();
                              });
                            },
                            child: Text(strings.grantPermission),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // 1. Connection Header Card
              _buildConnectionCard(bleManager, state, isConnected, strings),

              const SizedBox(height: 16),

              // 2. Battery & Live Signal Monitors (if connected)
              if (isConnected) ...[
                _buildLiveTelemetryCard(bleManager, strings),
                const SizedBox(height: 16),
                _buildOfflineStorageCard(bleManager, isConnected, strings),
                const SizedBox(height: 16),
              ],

              // 3. Paired Device Card (if device is remembered)
              if (bleManager.pairedDeviceId != null) ...[
                _buildPairedDeviceCard(bleManager, isConnected, strings),
                const SizedBox(height: 16),
              ],

              // 4. Mock Testing & Hardware Simulation Panel
              _buildSimulationPanel(bleManager, strings),

              const SizedBox(height: 16),

              // 5. Nearby Devices List (when scanning)
              _buildDiscoveredDevicesList(bleManager, strings),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConnectionCard(
      PolarBleManager bleManager, BleConnectionState state, bool isConnected, AppStrings strings) {
    String statusText;
    switch (state) {
      case BleConnectionState.connected:
        statusText = strings.connected;
        break;
      case BleConnectionState.streaming:
        statusText = strings.streaming;
        break;
      case BleConnectionState.connecting:
        statusText = strings.connecting;
        break;
      case BleConnectionState.scanning:
        statusText = strings.scanning;
        break;
      case BleConnectionState.disconnected:
        statusText = strings.disconnected;
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isConnected ? AppTheme.polarCyan : Colors.white12).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.bluetooth,
                    color: isConnected ? AppTheme.polarCyan : Colors.white54,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isConnected
                            ? (bleManager.connectedDeviceId ?? bleManager.pairedDeviceName ?? 'Polar Verity Sense')
                            : (bleManager.pairedDeviceName != null
                                ? '${bleManager.pairedDeviceName} (${strings.pairedDevice})'
                                : strings.noDeviceConnected),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${strings.status}: $statusText',
                        style: TextStyle(
                          fontSize: 12,
                          color: isConnected ? AppTheme.polarCyan : Colors.white38,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isConnected)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.polarRed,
                      side: const BorderSide(color: AppTheme.polarRed),
                    ),
                    onPressed: () => bleManager.disconnect(),
                    child: Text(strings.disconnect),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.polarCyan,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: state == BleConnectionState.scanning
                        ? null
                        : () => bleManager.searchForDevice(),
                    icon: state == BleConnectionState.scanning
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.search, size: 18),
                    label: Text(state == BleConnectionState.scanning ? strings.scanningBtn : strings.scanBle),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPairedDeviceCard(PolarBleManager bleManager, bool isConnected, AppStrings strings) {
    return Card(
      color: Colors.blueGrey.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blueGrey.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.bookmark_added, color: AppTheme.polarCyan, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.pairedDevice,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${bleManager.pairedDeviceName ?? "Polar Verity Sense"} (ID: ${bleManager.pairedDeviceId})',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isConnected ? strings.connected : strings.autoConnecting,
                    style: TextStyle(
                      fontSize: 11,
                      color: isConnected ? AppTheme.recoveryGood : Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
            if (!isConnected && bleManager.pairedDeviceId != null) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.polarCyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: bleManager.connectionState == BleConnectionState.connecting
                    ? null
                    : () => bleManager.connectToDevice(bleManager.pairedDeviceId!),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(
                  strings.reconnectNow,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
            ],
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppTheme.polarRed),
              onPressed: () => bleManager.forgetDevice(),
              child: Text(strings.forgetDevice),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalBadge(int rssi, AppStrings strings) {
    Color col;
    String label;
    if (rssi >= -60) {
      col = AppTheme.recoveryGood;
      label = strings.signalExcellent;
    } else if (rssi >= -75) {
      col = AppTheme.polarCyan;
      label = strings.signalGood;
    } else if (rssi >= -85) {
      col = Colors.amber;
      label = strings.signalFair;
    } else {
      col = AppTheme.polarRed;
      label = strings.signalWeak;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: col.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: col.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.network_wifi_3_bar, size: 13, color: col),
          const SizedBox(width: 4),
          Text(
            '$rssi dBm ($label)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: col),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTelemetryCard(PolarBleManager bleManager, AppStrings strings) {
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
                  strings.realtimeTelemetry,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                if (bleManager.lastRssi != null)
                  _buildSignalBadge(bleManager.lastRssi!, strings),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Battery & Charging status
                Expanded(
                  child: StreamBuilder<int>(
                    stream: bleManager.batteryStream,
                    initialData: bleManager.effectiveBatteryLevel,
                    builder: (context, snapshot) {
                      final battery = snapshot.data ?? bleManager.effectiveBatteryLevel;
                      final isReal = bleManager.batteryLevel != null;
                      final charging = bleManager.isCharging;
                      String batText = '--';
                      if (battery != null) {
                        batText = '$battery%';
                        if (charging) {
                          batText += ' ⚡';
                        } else if (!isReal) {
                          batText += ' (${strings.cachedStatus})';
                        }
                      }
                      return _buildMiniMetric(
                        charging ? Icons.battery_charging_full : Icons.battery_std,
                        batText,
                        strings.sensorBattery,
                        battery != null && battery > 20 ? AppTheme.recoveryGood : AppTheme.polarRed,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Live BPM
                Expanded(
                  child: StreamBuilder<int>(
                    stream: bleManager.hrStream,
                    initialData: bleManager.currentHr,
                    builder: (context, snapshot) {
                      final hr = snapshot.data ?? bleManager.currentHr ?? 0;
                      return _buildMiniMetric(
                        Icons.favorite,
                        hr > 0 ? '$hr ${strings.bpm}' : '--',
                        strings.opticalHr,
                        AppTheme.polarRed,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ACC Status (Checks streaming state rather than listening at 52Hz, preventing UI thread starvation)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.darkBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.sensors,
                    size: 16,
                    color: (bleManager.connectionState == BleConnectionState.streaming)
                        ? AppTheme.polarCyan
                        : Colors.white24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (bleManager.connectionState == BleConnectionState.streaming)
                          ? strings.accActive
                          : strings.accWaiting,
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineStorageCard(
      PolarBleManager bleManager, bool isConnected, AppStrings strings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.recoveryGood.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.sd_storage, color: AppTheme.recoveryGood, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.deviceMemory,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.memoryDetail,
                        style: const TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                StreamBuilder<bool>(
                  stream: bleManager.offlineRecordingStream,
                  initialData: bleManager.isOfflineRecording,
                  builder: (context, snapshot) {
                    final isRecording = snapshot.data ?? bleManager.isOfflineRecording;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (isRecording ? AppTheme.recoveryGood : Colors.white12).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isRecording ? AppTheme.recoveryGood : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isRecording ? Icons.fiber_manual_record : Icons.stop_circle_outlined,
                            size: 10,
                            color: isRecording ? AppTheme.recoveryGood : Colors.white54,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isRecording ? strings.recordingStatus : strings.offlineRecordingIdle,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isRecording ? AppTheme.recoveryGood : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              strings.offlineGuideStep2,
              style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.3),
            ),
            const SizedBox(height: 16),
            StreamBuilder<bool>(
              stream: bleManager.offlineRecordingStream,
              initialData: bleManager.isOfflineRecording,
              builder: (context, snapshot) {
                final isRecording = snapshot.data ?? bleManager.isOfflineRecording;
                return Row(
                  children: [
                    // Start or Stop Offline Recording Button
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRecording ? AppTheme.polarRed : AppTheme.recoveryGood,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: isConnected
                            ? () async {
                                if (isRecording) {
                                  await bleManager.stopOfflineRecording();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(strings.stopOfflineRecord)),
                                    );
                                  }
                                } else {
                                  await bleManager.startOfflineRecording();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(strings.offlineRecordingActive),
                                        backgroundColor: AppTheme.recoveryGood,
                                      ),
                                    );
                                  }
                                }
                              }
                            : null,
                        icon: Icon(isRecording ? Icons.stop : Icons.fiber_manual_record, size: 16),
                        label: Text(
                          isRecording ? strings.stopOfflineRecord : strings.startOfflineRecord,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Sync Button
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.polarCyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: isConnected
                            ? () async {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(strings.readingDeviceExercises),
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
                                      SnackBar(content: Text(strings.noExercisesFound)),
                                    );
                                  }
                                }
                              }
                            : null,
                        icon: const Icon(Icons.download_for_offline, size: 16),
                        label: Text(
                          strings.syncOfflineSleep,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMetric(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationPanel(PolarBleManager bleManager, AppStrings strings) {
    return Card(
      color: Colors.indigo.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.indigo.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.science, color: Colors.indigoAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.hardwareSimulator,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Switch(
                  value: bleManager.isMockMode,
                  activeColor: Colors.indigoAccent,
                  onChanged: (enable) {
                    setState(() {
                      bleManager.enableMockMode(enable);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              strings.hardwareSimulatorDesc,
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
            if (bleManager.isMockMode) ...[
              const Divider(color: Colors.white12, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    strings.simulateWalking,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  FilterChip(
                    label: Text(_mockWalking ? strings.walking : strings.stationary),
                    selected: _mockWalking,
                    selectedColor: AppTheme.recoveryGood.withOpacity(0.3),
                    checkmarkColor: AppTheme.recoveryGood,
                    onSelected: (val) {
                      setState(() {
                        _mockWalking = val;
                        bleManager.setMockWalking(val);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.indigoAccent,
                    side: const BorderSide(color: Colors.indigoAccent),
                  ),
                  onPressed: () async {
                    final session = await ref.read(sleepHistoryProvider.notifier).generateMockOfflineSleep();
                    if (context.mounted && session != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(strings.offlineSyncSuccess),
                          backgroundColor: AppTheme.recoveryGood,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.bedtime, size: 16),
                  label: Text(strings.generateMockOffline, style: const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveredDevicesList(PolarBleManager bleManager, AppStrings strings) {
    return StreamBuilder<List<DiscoveredDevice>>(
      stream: bleManager.discoveredDevicesStream,
      initialData: const [],
      builder: (context, snapshot) {
        final devices = snapshot.data ?? [];
        if (devices.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.discoveredDevices,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const Divider(color: AppTheme.darkBorder),
                  itemBuilder: (context, index) {
                    final dev = devices[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: AppTheme.darkBackground,
                        child: Icon(Icons.watch, color: AppTheme.polarCyan, size: 20),
                      ),
                      title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        'ID: ${dev.deviceId}  •  RSSI: ${dev.rssi} dBm',
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      trailing: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.polarCyan,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () => bleManager.connectToDevice(dev.deviceId, deviceName: dev.name),
                        child: Text(strings.connect),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
