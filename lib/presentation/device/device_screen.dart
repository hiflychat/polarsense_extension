import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ble/polar_ble_manager.dart';
import '../../features/sedentary/sedentary_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/pulse_indicator.dart';

class DeviceScreen extends ConsumerStatefulWidget {
  const DeviceScreen({super.key});

  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  bool _mockWalking = false;

  @override
  Widget build(BuildContext context) {
    final bleManager = ref.watch(polarBleManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Polar Verity Sense'),
        actions: [
          StreamBuilder<BleConnectionState>(
            stream: bleManager.stateStream,
            initialData: bleManager.connectionState,
            builder: (context, snapshot) {
              final isConnected = snapshot.data == BleConnectionState.connected ||
                  snapshot.data == BleConnectionState.streaming;

              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: PulseIndicator(
                    hr: null,
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
              // 1. Connection Header Card
              _buildConnectionCard(bleManager, state, isConnected),

              const SizedBox(height: 16),

              // 2. Battery & Live Signal Monitors (if connected)
              if (isConnected) ...[
                _buildLiveTelemetryCard(bleManager),
                const SizedBox(height: 16),
              ],

              // 3. Mock Testing & Hardware Simulation Panel
              _buildSimulationPanel(bleManager),

              const SizedBox(height: 16),

              // 4. Nearby Devices List (when scanning)
              _buildDiscoveredDevicesList(bleManager),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConnectionCard(
      PolarBleManager bleManager, BleConnectionState state, bool isConnected) {
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
                            ? (bleManager.connectedDeviceId ?? 'Polar Verity Sense')
                            : 'No Device Connected',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Status: ${state.name.toUpperCase()}',
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
                    child: const Text('Disconnect'),
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
                    label: Text(state == BleConnectionState.scanning ? 'Scanning...' : 'Scan BLE'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTelemetryCard(PolarBleManager bleManager) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Real-Time Sensor Telemetry',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Battery
                Expanded(
                  child: StreamBuilder<int>(
                    stream: bleManager.batteryStream,
                    initialData: 95,
                    builder: (context, snapshot) {
                      final battery = snapshot.data ?? 0;
                      return _buildMiniMetric(
                        Icons.battery_charging_full,
                        '$battery%',
                        'Sensor Battery',
                        battery > 20 ? AppTheme.recoveryGood : AppTheme.polarRed,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Live BPM
                Expanded(
                  child: StreamBuilder<int>(
                    stream: bleManager.hrStream,
                    builder: (context, snapshot) {
                      final hr = snapshot.data ?? 0;
                      return _buildMiniMetric(
                        Icons.favorite,
                        hr > 0 ? '$hr BPM' : '--',
                        'Optical HR',
                        AppTheme.polarRed,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // ACC Status
            StreamBuilder(
              stream: bleManager.accStream,
              builder: (context, snapshot) {
                final hasData = snapshot.hasData;
                return Container(
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
                        color: hasData ? AppTheme.polarCyan : Colors.white24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasData
                            ? 'ACC Stream 26 Hz: Active (arm posture synced)'
                            : 'ACC Stream: Waiting for samples...',
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
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
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
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

  Widget _buildSimulationPanel(PolarBleManager bleManager) {
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
                const Text(
                  'Hardware Simulator (Developer Mode)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
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
            const Text(
              'Simulate 26 Hz accelerometer and PPI streams without physical Polar Verity Sense.',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
            if (bleManager.isMockMode) ...[
              const Divider(color: Colors.white12, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Simulate Active Walking (VMU ≥ 0.15g)',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  FilterChip(
                    label: Text(_mockWalking ? 'Walking' : 'Stationary'),
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
              const SizedBox(height: 6),
              const Text(
                'Toggle to simulate 90 seconds continuous walking to test the sedentary timer reset.',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveredDevicesList(PolarBleManager bleManager) {
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
                const Text(
                  'Discovered Polar Devices',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
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
                        onPressed: () => bleManager.connectToDevice(dev.deviceId),
                        child: const Text('Connect'),
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
