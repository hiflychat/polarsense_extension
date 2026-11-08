import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:polar/polar.dart';
import 'polar_constants.dart';

enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  streaming,
}

class DiscoveredDevice {
  final String deviceId;
  final String name;
  final int rssi;
  final bool isConnectable;

  DiscoveredDevice({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.isConnectable,
  });
}

class PolarBleManager {
  final Polar _polar = Polar();

  bool _isMockMode = false;
  bool get isMockMode => _isMockMode;

  String? _connectedDeviceId;
  String? get connectedDeviceId => _connectedDeviceId;

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  BleConnectionState get connectionState => _connectionState;

  final _stateController = StreamController<BleConnectionState>.broadcast();
  Stream<BleConnectionState> get stateStream => _stateController.stream;

  final _discoveredDevicesController = StreamController<List<DiscoveredDevice>>.broadcast();
  Stream<List<DiscoveredDevice>> get discoveredDevicesStream => _discoveredDevicesController.stream;

  final _accStreamController = StreamController<PolarAccData>.broadcast();
  Stream<PolarAccData> get accStream => _accStreamController.stream;

  final _ppiStreamController = StreamController<PolarOhrPpiData>.broadcast();
  Stream<PolarOhrPpiData> get ppiStream => _ppiStreamController.stream;

  final _hrStreamController = StreamController<int>.broadcast();
  Stream<int> get hrStream => _hrStreamController.stream;

  final _batteryStreamController = StreamController<int>.broadcast();
  Stream<int> get batteryStream => _batteryStreamController.stream;

  final Map<String, DiscoveredDevice> _discoveredDevices = {};

  StreamSubscription? _deviceConnectedSub;
  StreamSubscription? _deviceDisconnectedSub;
  StreamSubscription? _batterySub;
  StreamSubscription? _featureReadySub;
  StreamSubscription? _accSub;
  StreamSubscription? _ppiSub;
  StreamSubscription? _hrSub;

  Timer? _mockAccTimer;
  Timer? _mockPpiTimer;
  Timer? _mockHrTimer;
  bool _mockIsWalking = false;
  int _reconnectAttempts = 0;
  bool _intentionalDisconnect = false;

  PolarBleManager() {
    _initPolarListeners();
  }

  void _initPolarListeners() {
    _deviceConnectedSub = _polar.deviceConnected.listen((info) {
      debugPrint('[BLE] Device connected: ${info.id}');
      _connectedDeviceId = info.id;
      _updateState(BleConnectionState.connected);
      _reconnectAttempts = 0;
    });

    _deviceDisconnectedSub = _polar.deviceDisconnected.listen((info) {
      debugPrint('[BLE] Device disconnected: ${info.id}');
      _updateState(BleConnectionState.disconnected);
      _connectedDeviceId = null;
      _cancelStreams();

      if (!_intentionalDisconnect) {
        _attemptAutoReconnect(info.id);
      }
    });

    _batterySub = _polar.batteryLevel.listen((event) {
      _batteryStreamController.add(event.level);
    });

    _featureReadySub = _polar.sdkFeatureReady.listen((event) {
      debugPrint('[BLE] SDK Feature ready: ${event.feature} on device: ${event.identifier}');
      final featureStr = event.feature.toString();
      if (featureStr.contains('onlineStreaming')) {
        _startStreaming(event.identifier);
      }
    });
  }

  void _updateState(BleConnectionState state) {
    _connectionState = state;
    _stateController.add(state);
  }

  void enableMockMode(bool enable) {
    if (_isMockMode == enable) return;
    _isMockMode = enable;
    if (enable) {
      disconnect();
      _connectedDeviceId = 'POLAR-MOCK-7A99';
      _updateState(BleConnectionState.connected);
      _startMockStreaming();
    } else {
      _stopMockStreaming();
      _connectedDeviceId = null;
      _updateState(BleConnectionState.disconnected);
    }
  }

  void setMockWalking(bool isWalking) {
    _mockIsWalking = isWalking;
  }

  Future<void> searchForDevice({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isMockMode) {
      _discoveredDevices['POLAR-MOCK-7A99'] = DiscoveredDevice(
        deviceId: 'POLAR-MOCK-7A99',
        name: 'Polar Verity Sense (Simulated)',
        rssi: -58,
        isConnectable: true,
      );
      _discoveredDevicesController.add(_discoveredDevices.values.toList());
      return;
    }

    _discoveredDevices.clear();
    _updateState(BleConnectionState.scanning);

    try {
      final searchSub = _polar.searchForDevice().listen((deviceInfo) {
        _discoveredDevices[deviceInfo.id] = DiscoveredDevice(
          deviceId: deviceInfo.id,
          name: deviceInfo.name.isNotEmpty ? deviceInfo.name : 'Polar Verity Sense',
          rssi: deviceInfo.rssi,
          isConnectable: deviceInfo.isConnectable,
        );
        _discoveredDevicesController.add(_discoveredDevices.values.toList());
      });

      Future.delayed(timeout, () {
        searchSub.cancel();
        if (_connectionState == BleConnectionState.scanning) {
          _updateState(BleConnectionState.disconnected);
        }
      });
    } catch (e) {
      debugPrint('[BLE] Search error: $e');
      _updateState(BleConnectionState.disconnected);
    }
  }

  Future<void> connectToDevice(String deviceId) async {
    _intentionalDisconnect = false;
    _updateState(BleConnectionState.connecting);

    if (_isMockMode) {
      _connectedDeviceId = deviceId;
      _updateState(BleConnectionState.connected);
      _startMockStreaming();
      return;
    }

    try {
      await _polar.connectToDevice(deviceId);
    } catch (e) {
      debugPrint('[BLE] Connection error: $e');
      _updateState(BleConnectionState.disconnected);
    }
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _cancelStreams();

    if (_isMockMode) {
      _stopMockStreaming();
      _connectedDeviceId = null;
      _updateState(BleConnectionState.disconnected);
      return;
    }

    if (_connectedDeviceId != null) {
      try {
        await _polar.disconnectFromDevice(_connectedDeviceId!);
      } catch (e) {
        debugPrint('[BLE] Disconnect error: $e');
      }
    }
    _connectedDeviceId = null;
    _updateState(BleConnectionState.disconnected);
  }

  void _attemptAutoReconnect(String deviceId) {
    if (_reconnectAttempts >= PolarConstants.maxReconnectAttempts) {
      debugPrint('[BLE] Max reconnect attempts reached for $deviceId');
      return;
    }

    _reconnectAttempts++;
    final delay = PolarConstants.initialReconnectDelay * (1 << (_reconnectAttempts - 1));
    debugPrint('[BLE] Scheduling auto-reconnect attempt #$_reconnectAttempts in ${delay.inSeconds}s');

    Timer(delay, () async {
      if (!_intentionalDisconnect && _connectionState == BleConnectionState.disconnected) {
        debugPrint('[BLE] Reconnecting to $deviceId...');
        await connectToDevice(deviceId);
      }
    });
  }

  Future<void> _startStreaming(String deviceId) async {
    try {
      _updateState(BleConnectionState.streaming);

      // 1. Accelerometer stream at 26 Hz
      _accSub?.cancel();
      _accSub = _polar.startAccStreaming(
        deviceId,
        sampleRate: PolarConstants.accSampleRate,
        range: PolarConstants.accRange,
      ).listen(
        (data) => _accStreamController.add(data),
        onError: (err) => debugPrint('[BLE] ACC stream error: $err'),
      );

      // 2. Optical Heart Rate PPI stream
      _ppiSub?.cancel();
      _ppiSub = _polar.startOhrPPIStreaming(deviceId).listen(
        (data) => _ppiStreamController.add(data),
        onError: (err) => debugPrint('[BLE] PPI stream error: $err'),
      );

      // 3. Heart Rate stream
      _hrSub?.cancel();
      _hrSub = _polar.startHrStreaming(deviceId).listen(
        (hrData) {
          if (hrData.samples.isNotEmpty) {
            _hrStreamController.add(hrData.samples.first.hr);
          }
        },
        onError: (err) => debugPrint('[BLE] HR stream error: $err'),
      );

      debugPrint('[BLE] All sensor streams started successfully');
    } catch (e) {
      debugPrint('[BLE] Error starting streams: $e');
    }
  }

  void _cancelStreams() {
    _accSub?.cancel();
    _accSub = null;
    _ppiSub?.cancel();
    _ppiSub = null;
    _hrSub?.cancel();
    _hrSub = null;
  }

  void _startMockStreaming() {
    _updateState(BleConnectionState.streaming);
    final random = Random();

    // 26 Hz ACC stream generation (every ~38ms, sends batches or per-sample)
    _mockAccTimer?.cancel();
    _mockAccTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final samples = <PolarAccSample>[];
      final now = DateTime.now();

      // Produce 3 samples per 100ms (~26Hz)
      for (int i = 0; i < 3; i++) {
        int x, y, z;
        if (_mockIsWalking) {
          // Walking pattern: dynamic swings ±250mg around 1g
          final angle = (timer.tick * 3 + i) * 0.4;
          x = (sin(angle) * 350).round();
          y = (1000 + cos(angle) * 300).round();
          z = (sin(angle * 0.5) * 200).round();
        } else {
          // Sedentary pattern: steady static gravity with tiny noise
          x = (random.nextDouble() * 20 - 10).round();
          y = (random.nextDouble() * 20 - 10).round();
          z = (1000 + random.nextDouble() * 20 - 10).round();
        }
        samples.add(PolarAccSample(
          timeStamp: now.subtract(Duration(milliseconds: (3 - i) * 38)),
          x: x,
          y: y,
          z: z,
        ));
      }
      _accStreamController.add(PolarAccData(samples: samples));
    });

    // PPI Beat-to-Beat generator (~1 beat per second)
    _mockPpiTimer?.cancel();
    _mockPpiTimer = Timer.periodic(const Duration(milliseconds: 850), (timer) {
      final ppiMs = 800 + random.nextInt(120);
      final sample = PolarOhrPpiSample(
        ppi: ppiMs,
        blockerBit: false,
        errorEstimate: 0,
        hr: (60000 / ppiMs).round(),
      );
      _ppiStreamController.add(PolarOhrPpiData(samples: [sample]));
      _hrStreamController.add((60000 / ppiMs).round());
    });

    _mockHrTimer?.cancel();
    _mockHrTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _batteryStreamController.add(88 + random.nextInt(10));
    });
  }

  void _stopMockStreaming() {
    _mockAccTimer?.cancel();
    _mockAccTimer = null;
    _mockPpiTimer?.cancel();
    _mockPpiTimer = null;
    _mockHrTimer?.cancel();
    _mockHrTimer = null;
  }

  void dispose() {
    _cancelStreams();
    _stopMockStreaming();
    _deviceConnectedSub?.cancel();
    _deviceDisconnectedSub?.cancel();
    _batterySub?.cancel();
    _featureReadySub?.cancel();
    _stateController.close();
    _discoveredDevicesController.close();
    _accStreamController.close();
    _ppiStreamController.close();
    _hrStreamController.close();
    _batteryStreamController.close();
  }
}
