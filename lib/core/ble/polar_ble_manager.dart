import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:polar/polar.dart';
import 'package:uuid/uuid.dart';
import '../database/health_database.dart';
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
  final HealthDatabase _database = HealthDatabase();

  bool _isMockMode = false;
  bool get isMockMode => _isMockMode;

  String? _connectedDeviceId;
  String? get connectedDeviceId => _connectedDeviceId;

  String? _pairedDeviceId;
  String? get pairedDeviceId => _pairedDeviceId;

  String? _pairedDeviceName;
  String? get pairedDeviceName => _pairedDeviceName;

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  BleConnectionState get connectionState => _connectionState;

  final _stateController = StreamController<BleConnectionState>.broadcast();
  Stream<BleConnectionState> get stateStream => _stateController.stream;

  final _discoveredDevicesController = StreamController<List<DiscoveredDevice>>.broadcast();
  Stream<List<DiscoveredDevice>> get discoveredDevicesStream => _discoveredDevicesController.stream;

  final _accStreamController = StreamController<PolarAccData>.broadcast();
  Stream<PolarAccData> get accStream => _accStreamController.stream;

  final _ppiStreamController = StreamController<PolarPpiData>.broadcast();
  Stream<PolarPpiData> get ppiStream => _ppiStreamController.stream;

  final _hrStreamController = StreamController<int>.broadcast();
  Stream<int> get hrStream => _hrStreamController.stream;

  final _batteryStreamController = StreamController<int>.broadcast();
  Stream<int> get batteryStream => _batteryStreamController.stream;

  final _chargingStreamController = StreamController<bool>.broadcast();
  Stream<bool> get chargingStream => _chargingStreamController.stream;

  final _offlineRecordingController = StreamController<bool>.broadcast();
  Stream<bool> get offlineRecordingStream => _offlineRecordingController.stream;

  bool _isOfflineRecording = false;
  bool get isOfflineRecording => _isOfflineRecording;

  bool _isSyncingOffline = false;
  bool get isSyncingOffline => _isSyncingOffline;

  final Set<PolarSdkFeature> _readyFeatures = {};
  Set<PolarSdkFeature> get readyFeatures => Set.unmodifiable(_readyFeatures);

  String? _lastSyncError;
  String? get lastSyncError => _lastSyncError;

  Map<String, dynamic>? _lastStorageDiagnostics;
  Map<String, dynamic>? get lastStorageDiagnostics => _lastStorageDiagnostics;

  final List<PolarExerciseEntry> _mockStoredExercises = [];
  List<PolarExerciseEntry> get mockStoredExercises => List.unmodifiable(_mockStoredExercises);

  final Map<String, DiscoveredDevice> _discoveredDevices = {};

  int? _batteryLevel;
  int? get batteryLevel => _batteryLevel;

  int? _cachedBatteryLevel;
  int? get cachedBatteryLevel => _cachedBatteryLevel;

  int? get effectiveBatteryLevel => _batteryLevel ?? _cachedBatteryLevel;

  bool _isCharging = false;
  bool get isCharging => _isCharging;

  int? _currentHr;
  int? get currentHr => _currentHr;

  int? _lastRssi;
  int? get lastRssi => _lastRssi;

  DateTime? _lastSampleReceivedTime;
  DateTime? _lastHrEmitTime;
  DateTime? _lastDiscoveredEmitTime;
  DateTime? _lastHealingAttempt;
  Timer? _streamWatchdogTimer;
  Timer? _startupFallbackTimer;
  Timer? _batterySyncTimer;

  StreamSubscription? _deviceConnectedSub;
  StreamSubscription? _deviceDisconnectedSub;
  StreamSubscription? _batterySub;
  StreamSubscription? _batteryChargingSub;
  StreamSubscription? _featuresReadinessSub;
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
  bool _isStartingStreams = false;

  void _safeAdd<T>(StreamController<T> controller, T event) {
    if (!controller.isClosed) {
      controller.add(event);
    }
  }

  /// Deduplicates and throttles live heart rate emissions to avoid UI thread flooding (max 1 event / 800ms)
  void _updateCurrentHr(int hr) {
    _currentHr = hr;
    final now = DateTime.now();
    if (_lastHrEmitTime == null ||
        now.difference(_lastHrEmitTime!) >= const Duration(milliseconds: 800)) {
      _lastHrEmitTime = now;
      _safeAdd(_hrStreamController, hr);
    }
  }

  /// Safely check whether required Bluetooth runtime permissions have been granted
  static Future<bool> hasBlePermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    try {
      final connectGranted = await Permission.bluetoothConnect.isGranted;
      final scanGranted = await Permission.bluetoothScan.isGranted;
      return connectGranted && scanGranted;
    } catch (e) {
      debugPrint('[BLE] Error checking permissions: $e');
      return false;
    }
  }

  /// Request Bluetooth runtime permissions from user
  static Future<bool> requestBlePermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
        Permission.notification,
      ].request();

      final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? true;
      final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? true;
      return connectGranted && scanGranted;
    } catch (e) {
      debugPrint('[BLE] Error requesting permissions: $e');
      return false;
    }
  }

  PolarBleManager() {
    _initPolarListeners();
    _loadPairedDeviceAndAutoConnect();
  }

  void _initPolarListeners() {
    _deviceConnectedSub = _polar.deviceConnected.listen((info) {
      debugPrint('[BLE] Device connected: ${info.deviceId}');
      _connectedDeviceId = info.deviceId;
      _readyFeatures.clear();
      _updateState(BleConnectionState.connected);
      _reconnectAttempts = 0;

      // Remember device
      final name = _discoveredDevices[info.deviceId]?.name ?? _pairedDeviceName ?? 'Polar Verity Sense';
      savePairedDevice(info.deviceId, name);

      // If we have a cached battery level, supply it initially so UI is not empty
      if (_batteryLevel == null && _cachedBatteryLevel != null) {
        _safeAdd(_batteryStreamController, _cachedBatteryLevel!);
      }

      // Immediately check native wrapper cache in case BAS/features fired during handshake
      _syncCachedStatusFromNative(info.deviceId);

      // Staggered battery cache re-check at 1.5s & 3s if real battery hasn't pushed yet
      _batterySyncTimer?.cancel();
      _batterySyncTimer = Timer(const Duration(milliseconds: 1500), () {
        if (_connectedDeviceId == info.deviceId && _batteryLevel == null) {
          _syncCachedStatusFromNative(info.deviceId);
        }
      });

      // Safety fallback: if readiness callbacks delay, prioritize HR first, then PMD ACC+PPI
      _startupFallbackTimer?.cancel();
      _startupFallbackTimer = Timer(const Duration(milliseconds: 4500), () {
        if (_connectedDeviceId == info.deviceId &&
            (_connectionState == BleConnectionState.connected ||
                _connectionState == BleConnectionState.streaming) &&
            !_isSyncingOffline) {
          debugPrint('[BLE] Startup readiness fallback -> ensuring HR & PMD streams');
          _syncCachedStatusFromNative(info.deviceId);
          _startHrStreamIfNeeded(info.deviceId);
          if (_accSub == null || _ppiSub == null) {
            _startSensorStreams(info.deviceId);
          }
        }
      });
    }, onError: (err) {
      debugPrint('[BLE] deviceConnected stream error: $err');
    });

    _deviceDisconnectedSub = _polar.deviceDisconnected.listen((event) {
      debugPrint('[BLE] Device disconnected: ${event.info.deviceId}');
      _startupFallbackTimer?.cancel();
      _startupFallbackTimer = null;
      _batterySyncTimer?.cancel();
      _batterySyncTimer = null;
      _updateState(BleConnectionState.disconnected);
      _connectedDeviceId = null;
      _readyFeatures.clear();
      _batteryLevel = null;
      _isCharging = false;
      _currentHr = null;
      _isOfflineRecording = false;
      _isSyncingOffline = false;
      _isStartingStreams = false;
      _safeAdd(_offlineRecordingController, false);
      _safeAdd(_chargingStreamController, false);
      _cancelStreams();

      if (!_intentionalDisconnect) {
        _attemptAutoReconnect(event.info.deviceId);
      }
    }, onError: (err) {
      debugPrint('[BLE] deviceDisconnected stream error: $err');
    });

    _batterySub = _polar.batteryLevel.listen((event) {
      debugPrint('[BLE] Real battery level received: ${event.level}% for ${event.identifier}');
      if (_batteryLevel != event.level) {
        _batteryLevel = event.level;
        _cachedBatteryLevel = event.level;
        _safeAdd(_batteryStreamController, event.level);
        // Persist latest known battery level asynchronously without blocking callbacks
        unawaited(_database.setSetting('last_battery_level', event.level.toString()));
      }
    }, onError: (err) {
      debugPrint('[BLE] batteryLevel stream error: $err');
    });

    _batteryChargingSub = _polar.batteryChargingStatus.listen((event) {
      debugPrint('[BLE] Battery charging status: ${event.chargingStatus} on ${event.identifier}');
      final charging = event.chargingStatus == PolarChargeState.charging;
      if (_isCharging != charging) {
        _isCharging = charging;
        _safeAdd(_chargingStreamController, charging);
      }
    }, onError: (err) {
      debugPrint('[BLE] batteryChargingStatus stream error: $err');
    });

    _featuresReadinessSub = _polar.sdkFeaturesReadiness.listen((event) {
      debugPrint('[BLE] SDK Features readiness: ${event.ready} for ${event.identifier}');
      if (event.identifier == _connectedDeviceId && !_isSyncingOffline) {
        _readyFeatures.addAll(event.ready);
        if (event.ready.contains(PolarSdkFeature.batteryInfo)) {
          _syncCachedStatusFromNative(event.identifier);
        }
        if (event.ready.contains(PolarSdkFeature.hr)) {
          _startHrStreamIfNeeded(event.identifier);
        }
        if (event.ready.contains(PolarSdkFeature.onlineStreaming)) {
          _schedulePmdStartup(event.identifier);
        }
      }
    }, onError: (err) {
      debugPrint('[BLE] sdkFeaturesReadiness stream error: $err');
    });

    _featureReadySub = _polar.sdkFeatureReady.listen((event) {
      debugPrint('[BLE] SDK Feature ready: ${event.feature} on ${event.identifier}');
      if (event.identifier == _connectedDeviceId && !_isSyncingOffline) {
        _readyFeatures.add(event.feature);
        if (event.feature == PolarSdkFeature.batteryInfo) {
          _syncCachedStatusFromNative(event.identifier);
        } else if (event.feature == PolarSdkFeature.hr) {
          // Start Standard BLE Heart Rate Service immediately without waiting for PMD
          _startHrStreamIfNeeded(event.identifier);
        } else if (event.feature == PolarSdkFeature.onlineStreaming) {
          _schedulePmdStartup(event.identifier);
        }
      }
    }, onError: (err) {
      debugPrint('[BLE] sdkFeatureReady stream error: $err');
    });
  }

  Future<void> _syncCachedStatusFromNative(String deviceId) async {
    if (_connectedDeviceId != deviceId || _isMockMode) return;
    try {
      final cached = await _polar.getCachedDeviceStatus(deviceId);
      if (_connectedDeviceId != deviceId) return;

      final bat = cached['batteryLevel'];
      if (bat is int && bat >= 0 && bat <= 100 && _batteryLevel != bat) {
        _batteryLevel = bat;
        _cachedBatteryLevel = bat;
        _safeAdd(_batteryStreamController, bat);
        unawaited(_database.setSetting('last_battery_level', bat.toString()));
      }

      final chargingStr = cached['chargingStatus'] as String?;
      if (chargingStr != null) {
        final ch = chargingStr.toUpperCase() == 'CHARGING';
        if (_isCharging != ch) {
          _isCharging = ch;
          _safeAdd(_chargingStreamController, ch);
        }
      }

      final feats = cached['readyFeatures'];
      if (feats is List) {
        for (final f in feats) {
          try {
            _readyFeatures.add(PolarSdkFeature.fromJson(f.toString()));
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[BLE] Cached status sync skipped: $e');
    }
  }

  /// Yields briefly before launching heavy PMD (ACC + PPI) streams so BAS (Battery 0x180F)
  /// and standard HRS (Heart Rate 0x180D) complete their initial GATT reads/CCCD writes first.
  void _schedulePmdStartup(String deviceId) {
    if (_isStartingStreams || _isSyncingOffline || _connectedDeviceId != deviceId) return;
    if (_accSub != null && _ppiSub != null) return;

    final delayMs = (_readyFeatures.contains(PolarSdkFeature.batteryInfo) &&
            _readyFeatures.contains(PolarSdkFeature.hr))
        ? 250
        : 1000;

    Future.delayed(Duration(milliseconds: delayMs), () {
      if (_connectedDeviceId == deviceId && !_isSyncingOffline) {
        _startSensorStreams(deviceId);
      }
    });
  }

  /// Starts lightweight standard BLE Heart Rate Service (0x180D) independently of PMD streams.
  void _startHrStreamIfNeeded(String deviceId) {
    if (_isMockMode || _isSyncingOffline || _connectedDeviceId != deviceId) return;
    if (_hrSub != null) return;

    try {
      debugPrint('[BLE] Starting standard HR stream (0x180D) for $deviceId');
      _hrSub = _polar.startHrStreaming(deviceId).listen(
        (hrData) {
          _lastSampleReceivedTime = DateTime.now();
          for (final sample in hrData.samples) {
            if (sample.hr > 0 && sample.hr < 250) {
              _updateCurrentHr(sample.hr);
            }
          }
          if (_connectionState == BleConnectionState.connected) {
            _updateState(BleConnectionState.streaming);
          }
        },
        onError: (err) {
          debugPrint('[BLE] HR stream error: $err');
          _hrSub?.cancel();
          _hrSub = null;
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[BLE] Error starting HR stream: $e');
      _hrSub = null;
    }
  }

  Future<void> _loadPairedDeviceAndAutoConnect() async {
    try {
      _pairedDeviceId = await _database.getSetting('paired_device_id');
      _pairedDeviceName = await _database.getSetting('paired_device_name');
      final lastBat = await _database.getSetting('last_battery_level');
      if (lastBat != null) {
        _cachedBatteryLevel = int.tryParse(lastBat);
        if (_cachedBatteryLevel != null) {
          _safeAdd(_batteryStreamController, _cachedBatteryLevel!);
        }
      }
      debugPrint('[BLE] Loaded paired device: $_pairedDeviceId ($_pairedDeviceName), cachedBat: $_cachedBatteryLevel');

      if (_pairedDeviceId != null &&
          _connectionState == BleConnectionState.disconnected &&
          !_isMockMode) {
        final hasPerms = await hasBlePermissions();
        if (hasPerms) {
          debugPrint('[BLE] Permissions verified, auto-connecting to $_pairedDeviceId');
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (_connectionState == BleConnectionState.disconnected && !_intentionalDisconnect) {
              connectToDevice(_pairedDeviceId!, deviceName: _pairedDeviceName);
            }
          });
        } else {
          debugPrint('[BLE] Permissions not yet granted, skipping startup auto-connect');
        }
      }
    } catch (e) {
      debugPrint('[BLE] Error loading paired device: $e');
    }
  }

  Future<void> savePairedDevice(String deviceId, String name) async {
    _pairedDeviceId = deviceId;
    _pairedDeviceName = name;
    try {
      await _database.setSetting('paired_device_id', deviceId);
      await _database.setSetting('paired_device_name', name);
      debugPrint('[BLE] Saved paired device: $deviceId ($name)');
    } catch (e) {
      debugPrint('[BLE] Error saving paired device: $e');
    }
  }

  Future<void> forgetDevice() async {
    await disconnect();
    _pairedDeviceId = null;
    _pairedDeviceName = null;
    try {
      await _database.removeSetting('paired_device_id');
      await _database.removeSetting('paired_device_name');
      debugPrint('[BLE] Removed paired device from persistent storage');
    } catch (e) {
      debugPrint('[BLE] Error forgetting device: $e');
    }
    _updateState(BleConnectionState.disconnected);
  }

  void _updateState(BleConnectionState state) {
    _connectionState = state;
    _safeAdd(_stateController, state);
  }

  void enableMockMode(bool enable) {
    if (_isMockMode == enable) return;
    _isMockMode = enable;
    if (enable) {
      disconnect();
      _connectedDeviceId = 'POLAR-MOCK-7A99';
      _batteryLevel = 90;
      _cachedBatteryLevel = 90;
      _isCharging = false;
      _currentHr = 72;
      _updateState(BleConnectionState.connected);
      _startMockStreaming();
    } else {
      _stopMockStreaming();
      _connectedDeviceId = null;
      _batteryLevel = null;
      _isCharging = false;
      _currentHr = null;
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
      _safeAdd(_discoveredDevicesController, _discoveredDevices.values.toList());
      return;
    }

    // Check & request Bluetooth permissions first
    final hasPerms = await requestBlePermissions();
    if (!hasPerms) {
      debugPrint('[BLE] Search aborted: Bluetooth permissions not granted');
      _updateState(BleConnectionState.disconnected);
      return;
    }

    _discoveredDevices.clear();
    _lastDiscoveredEmitTime = null;
    _updateState(BleConnectionState.scanning);

    try {
      final searchSub = _polar.searchForDevice().listen(
        (deviceInfo) {
          if (deviceInfo.deviceId == _connectedDeviceId || deviceInfo.deviceId == _pairedDeviceId) {
            _lastRssi = deviceInfo.rssi;
          }
          _discoveredDevices[deviceInfo.deviceId] = DiscoveredDevice(
            deviceId: deviceInfo.deviceId,
            name: deviceInfo.name.isNotEmpty ? deviceInfo.name : 'Polar Verity Sense',
            rssi: deviceInfo.rssi,
            isConnectable: deviceInfo.isConnectable,
          );

          // Throttle discovered devices stream to at most once every 600ms to avoid UI jank
          final now = DateTime.now();
          if (_lastDiscoveredEmitTime == null ||
              now.difference(_lastDiscoveredEmitTime!) >= const Duration(milliseconds: 600)) {
            _lastDiscoveredEmitTime = now;
            _safeAdd(_discoveredDevicesController, _discoveredDevices.values.toList());
          }
        },
        onError: (err) {
          debugPrint('[BLE] Search stream error: $err');
          if (_connectionState == BleConnectionState.scanning) {
            _updateState(BleConnectionState.disconnected);
          }
        },
      );

      Future.delayed(timeout, () {
        searchSub.cancel();
        _safeAdd(_discoveredDevicesController, _discoveredDevices.values.toList());
        if (_connectionState == BleConnectionState.scanning) {
          _updateState(BleConnectionState.disconnected);
        }
      });
    } catch (e) {
      debugPrint('[BLE] Search error: $e');
      _updateState(BleConnectionState.disconnected);
    }
  }

  Future<bool> connectToDevice(String deviceId, {String? deviceName}) async {
    _intentionalDisconnect = false;

    if (_isMockMode) {
      _connectedDeviceId = deviceId;
      _batteryLevel = 90;
      _cachedBatteryLevel = 90;
      _isCharging = false;
      _currentHr = 72;
      _updateState(BleConnectionState.connected);
      _startMockStreaming();
      return true;
    }

    // Check & request Bluetooth permissions before touching native stack
    final hasPerms = await requestBlePermissions();
    if (!hasPerms) {
      debugPrint('[BLE] Connect aborted: Bluetooth permissions not granted');
      _updateState(BleConnectionState.disconnected);
      return false;
    }

    _updateState(BleConnectionState.connecting);

    final name = deviceName ?? _discoveredDevices[deviceId]?.name ?? _pairedDeviceName ?? 'Polar Verity Sense';
    await savePairedDevice(deviceId, name);

    try {
      debugPrint('[BLE] Connecting to Polar device: $deviceId');
      await _polar.connectToDevice(deviceId).timeout(const Duration(seconds: 12));
      return true;
    } catch (e) {
      debugPrint('[BLE] Connection error or timeout: $e');
      _updateState(BleConnectionState.disconnected);
      return false;
    }
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _cancelStreams();

    if (_isMockMode) {
      _stopMockStreaming();
      _connectedDeviceId = null;
      _batteryLevel = null;
      _isCharging = false;
      _currentHr = null;
      _updateState(BleConnectionState.disconnected);
      return;
    }

    if (_connectedDeviceId != null) {
      try {
        await _polar.disconnectFromDevice(_connectedDeviceId!).timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('[BLE] Disconnect error: $e');
      }
    }
    _connectedDeviceId = null;
    _batteryLevel = null;
    _isCharging = false;
    _currentHr = null;
    _isStartingStreams = false;
    _updateState(BleConnectionState.disconnected);
  }

  void _attemptAutoReconnect(String deviceId) {
    if (_isMockMode || _reconnectAttempts >= PolarConstants.maxReconnectAttempts) {
      debugPrint('[BLE] Max reconnect attempts reached for $deviceId');
      return;
    }

    _reconnectAttempts++;
    final delay = PolarConstants.initialReconnectDelay * (1 << (_reconnectAttempts - 1));
    debugPrint('[BLE] Scheduling auto-reconnect attempt #$_reconnectAttempts in ${delay.inSeconds}s');

    Timer(delay, () async {
      if (!_intentionalDisconnect && _connectionState == BleConnectionState.disconnected) {
        final hasPerms = await hasBlePermissions();
        if (hasPerms) {
          debugPrint('[BLE] Auto-reconnecting to $deviceId...');
          await connectToDevice(deviceId);
        }
      }
    });
  }

  Future<void> _startSensorStreams(String deviceId) async {
    if (_isStartingStreams || _isSyncingOffline || _connectedDeviceId != deviceId) return;
    _isStartingStreams = true;

    try {
      debugPrint('[BLE] Starting balanced sensor streams for $deviceId');

      // 0. Ensure Standard BLE Heart Rate Service (0x180D) is active if HR feature is ready
      if (_hrSub == null &&
          (_readyFeatures.contains(PolarSdkFeature.hr) || _readyFeatures.isEmpty)) {
        _startHrStreamIfNeeded(deviceId);
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (_connectedDeviceId != deviceId || _isSyncingOffline) return;

      // 1. Accelerometer Stream: query supported settings ONCE and pick 26Hz (if supported) or 52Hz
      // instead of calling startAccStreaming(settings: null) which invokes maxSettings()!
      if (_accSub == null) {
        PolarSensorSetting? accSetting;
        try {
          final available = await _polar
              .requestStreamSettings(deviceId, PolarDataType.acc)
              .timeout(const Duration(seconds: 4));
          accSetting = resolveOptimalAccSettings(available);
          debugPrint('[BLE] Resolved optimal ACC settings: ${accSetting.settings}');
        } catch (e) {
          debugPrint('[BLE] requestStreamSettings(ACC) fallback: $e');
          accSetting = resolveOptimalAccSettings();
        }

        if (_connectedDeviceId != deviceId || _isSyncingOffline) return;

        try {
          _accSub = _polar
              .startAccStreaming(deviceId, settings: accSetting)
              .listen(
            (data) {
              _lastSampleReceivedTime = DateTime.now();
              _safeAdd(_accStreamController, data);
            },
            onError: (err) {
              debugPrint('[BLE] ACC stream error: $err');
              _accSub?.cancel();
              _accSub = null;
            },
            cancelOnError: false,
          );
        } catch (e) {
          debugPrint('[BLE] Error starting ACC stream: $e');
          _accSub = null;
        }

        // Stagger PMD writes to prevent Android GATT status 133 collisions
        await Future.delayed(const Duration(milliseconds: 350));
        if (_connectedDeviceId != deviceId || _isSyncingOffline) return;
      }

      // 2. Optical Heart Rate PPI Stream (instantaneous optical pulse-to-pulse intervals + HR)
      if (_ppiSub == null) {
        try {
          debugPrint('[BLE] Starting Optical PPI stream for $deviceId');
          _ppiSub = _polar.startPpiStreaming(deviceId).listen(
            (ppiData) {
              _lastSampleReceivedTime = DateTime.now();
              _safeAdd(_ppiStreamController, ppiData);
              for (final sample in ppiData.samples) {
                if (sample.hr > 0 && sample.hr < 250) {
                  _updateCurrentHr(sample.hr);
                }
              }
            },
            onError: (err) {
              debugPrint('[BLE] PPI stream error: $err');
              _ppiSub?.cancel();
              _ppiSub = null;
            },
            cancelOnError: false,
          );
        } catch (e) {
          debugPrint('[BLE] Error starting PPI stream: $e');
          _ppiSub = null;
        }
      }

      if (_connectedDeviceId != deviceId || _isSyncingOffline) return;
      _lastSampleReceivedTime = DateTime.now();
      _updateState(BleConnectionState.streaming);
      _startStreamWatchdog(deviceId);
    } catch (e) {
      debugPrint('[BLE] Error in _startSensorStreams: $e');
    } finally {
      _isStartingStreams = false;
    }
  }

  /// Selects balanced actigraphy settings (prefers 26 Hz if supported by the sensor,
  /// otherwise native 52 Hz with 8G range, 16-bit, 3 channels) instead of maxSettings()
  /// (which can pick 208/416 Hz in SDK mode and overwhelm BLE/UI event channels).
  static PolarSensorSetting resolveOptimalAccSettings([PolarSensorSetting? available]) {
    if (available == null || available.settings.isEmpty) {
      return PolarSensorSetting({
        PolarSettingType.sampleRate: PolarConstants.accSampleRate,
        PolarSettingType.range: PolarConstants.accRange,
        PolarSettingType.resolution: 16,
        PolarSettingType.channels: 3,
      });
    }

    final selected = <PolarSettingType, int>{};
    final s = available.settings;

    final rates = s[PolarSettingType.sampleRate];
    if (rates != null && rates.isNotEmpty) {
      final sorted = List<int>.from(rates)..sort();
      if (sorted.contains(PolarConstants.preferredAccSampleRate)) {
        selected[PolarSettingType.sampleRate] = PolarConstants.preferredAccSampleRate;
      } else if (sorted.contains(PolarConstants.accSampleRate)) {
        selected[PolarSettingType.sampleRate] = PolarConstants.accSampleRate;
      } else {
        selected[PolarSettingType.sampleRate] = sorted.firstWhere(
          (r) => r >= PolarConstants.preferredAccSampleRate,
          orElse: () => sorted.last,
        );
      }
    } else {
      selected[PolarSettingType.sampleRate] = PolarConstants.accSampleRate;
    }

    final ranges = s[PolarSettingType.range];
    if (ranges != null && ranges.isNotEmpty) {
      final sorted = List<int>.from(ranges)..sort();
      selected[PolarSettingType.range] = sorted.contains(PolarConstants.accRange)
          ? PolarConstants.accRange
          : sorted.firstWhere((r) => r >= 4, orElse: () => sorted.last);
    }

    final resolutions = s[PolarSettingType.resolution];
    if (resolutions != null && resolutions.isNotEmpty) {
      final sorted = List<int>.from(resolutions)..sort();
      selected[PolarSettingType.resolution] =
          sorted.contains(16) ? 16 : sorted.first;
    }

    final channels = s[PolarSettingType.channels];
    if (channels != null && channels.isNotEmpty) {
      selected[PolarSettingType.channels] =
          channels.contains(3) ? 3 : channels.first;
    }

    final rangeMilli = s[PolarSettingType.rangeMilliunit];
    if (rangeMilli != null && rangeMilli.isNotEmpty) {
      selected[PolarSettingType.rangeMilliunit] = rangeMilli.first;
    }

    return PolarSensorSetting(selected);
  }

  void _startStreamWatchdog(String deviceId) {
    _streamWatchdogTimer?.cancel();
    _streamWatchdogTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (_connectedDeviceId != deviceId || _connectionState != BleConnectionState.streaming) {
        timer.cancel();
        return;
      }
      if (_isMockMode || _isSyncingOffline) return;

      // Gently re-sync battery if still unknown
      if (_batteryLevel == null) {
        _syncCachedStatusFromNative(deviceId);
      }

      // Recover HR stream independently without tearing down healthy ACC/PPI streams
      if (_hrSub == null && _readyFeatures.contains(PolarSdkFeature.hr)) {
        _startHrStreamIfNeeded(deviceId);
      }

      final now = DateTime.now();
      // Full heal only when ALL telemetry has completely stalled for > 35 seconds
      if (_lastSampleReceivedTime != null &&
          now.difference(_lastSampleReceivedTime!) > const Duration(seconds: 35)) {
        if (_lastHealingAttempt == null ||
            now.difference(_lastHealingAttempt!) > const Duration(seconds: 45)) {
          _lastHealingAttempt = now;
          debugPrint('[BLE Watchdog] All streams stalled >35s! Healing for $deviceId...');
          _healSensorStreams(deviceId);
        }
      }
    });
  }

  Future<void> _healSensorStreams(String deviceId) async {
    if (_connectedDeviceId != deviceId || _isStartingStreams) return;
    debugPrint('[BLE Watchdog] Restarting stalled streams on $deviceId');
    _cancelStreams();
    _lastSampleReceivedTime = DateTime.now();
    await _startSensorStreams(deviceId);
  }

  void _cancelStreams() {
    _streamWatchdogTimer?.cancel();
    _streamWatchdogTimer = null;
    _accSub?.cancel();
    _accSub = null;
    _ppiSub?.cancel();
    _ppiSub = null;
    _hrSub?.cancel();
    _hrSub = null;
  }

  Future<void> _cancelStreamsAsync() async {
    _streamWatchdogTimer?.cancel();
    _streamWatchdogTimer = null;
    final futures = <Future<void>>[];
    if (_accSub != null) futures.add(_accSub!.cancel());
    if (_ppiSub != null) futures.add(_ppiSub!.cancel());
    if (_hrSub != null) futures.add(_hrSub!.cancel());
    _accSub = null;
    _ppiSub = null;
    _hrSub = null;
    if (futures.isNotEmpty) {
      await Future.wait(futures).catchError((_) => <void>[]);
    }
  }

  void _startMockStreaming() {
    _updateState(BleConnectionState.streaming);
    final random = Random();

    // 26 Hz ACC stream generation
    _mockAccTimer?.cancel();
    _mockAccTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final samples = <PolarAccSample>[];
      final now = DateTime.now();

      for (int i = 0; i < 3; i++) {
        int x, y, z;
        if (_mockIsWalking) {
          final angle = (timer.tick * 3 + i) * 0.4;
          x = (sin(angle) * 350).round();
          y = (1000 + cos(angle) * 300).round();
          z = (sin(angle * 0.5) * 200).round();
        } else {
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
      _safeAdd(_accStreamController, PolarAccData(samples: samples));
    });

    // PPI & HR stream generation
    _mockPpiTimer?.cancel();
    _mockPpiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final ppiMs = 800 + (sin(timer.tick * 0.2) * 50).round() + (random.nextInt(20) - 10);
      final sample = PolarPpiSample(
        timeStamp: DateTime.now().millisecondsSinceEpoch,
        ppi: ppiMs,
        errorEstimate: 5,
        hr: (60000 / ppiMs).round(),
        blockerBit: false,
        skinContactStatus: true,
        skinContactSupported: true,
      );
      _safeAdd(_ppiStreamController, PolarPpiData(samples: [sample]));
      final hr = (60000 / ppiMs).round();
      _currentHr = hr;
      _safeAdd(_hrStreamController, hr);
    });

    _mockHrTimer?.cancel();
    _mockHrTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final b = 88 + random.nextInt(10);
      _batteryLevel = b;
      _cachedBatteryLevel = b;
      _safeAdd(_batteryStreamController, b);
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

  /// Check whether the sensor is currently recording offline internally
  Future<PolarRecordingStatus?> checkOfflineRecordingStatus() async {
    if (_isMockMode) {
      final status = PolarRecordingStatus(
        ongoing: _isOfflineRecording,
        entryId: _isOfflineRecording ? 'mock-active-recording' : '',
      );
      _safeAdd(_offlineRecordingController, _isOfflineRecording);
      return status;
    }

    if (_connectedDeviceId == null) return null;

    try {
      final status = await _polar
          .requestRecordingStatus(_connectedDeviceId!)
          .timeout(const Duration(seconds: 4));
      _isOfflineRecording = status.ongoing;
      _safeAdd(_offlineRecordingController, status.ongoing);
      debugPrint('[BLE] Sensor offline recording status: ${status.ongoing}, entryId: ${status.entryId}');
      return status;
    } catch (e) {
      debugPrint('[BLE] Error requesting recording status: $e');
      return null;
    }
  }

  /// Start offline standalone recording directly into sensor flash memory
  Future<bool> startOfflineRecording({
    SampleType sampleType = SampleType.rr,
    RecordingInterval interval = RecordingInterval.interval_1s,
  }) async {
    if (_isMockMode) {
      _isOfflineRecording = true;
      _safeAdd(_offlineRecordingController, true);
      debugPrint('[BLE] [MOCK] Standalone offline recording started');
      return true;
    }

    if (_connectedDeviceId == null) {
      debugPrint('[BLE] Cannot start recording: device not connected');
      return false;
    }

    final deviceId = _connectedDeviceId!;
    try {
      // Polar Verity Sense forbids running online PPI streaming and offline PPI recording concurrently.
      // Pause online streams before initiating offline recording so PMD state does not collide.
      if (_connectionState == BleConnectionState.streaming) {
        await _cancelStreamsAsync();
        _updateState(BleConnectionState.connected);
        await Future.delayed(const Duration(milliseconds: 600));
      }

      final exerciseId = const Uuid().v4();
      try {
        await _polar
            .startRecording(
              deviceId,
              exerciseId: exerciseId,
              interval: interval,
              sampleType: sampleType,
            )
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        if (sampleType == SampleType.rr) {
          debugPrint('[BLE] PPI offline recording failed ($e), falling back to HR offline recording...');
          await _polar
              .startRecording(
                deviceId,
                exerciseId: exerciseId,
                interval: interval,
                sampleType: SampleType.hr,
              )
              .timeout(const Duration(seconds: 8));
        } else {
          rethrow;
        }
      }
      _isOfflineRecording = true;
      _safeAdd(_offlineRecordingController, true);
      debugPrint('[BLE] Standalone offline recording started on $deviceId (id: $exerciseId)');
      return true;
    } catch (e) {
      debugPrint('[BLE] Failed to start offline recording: $e');
      return false;
    }
  }

  /// Stop offline standalone recording on sensor
  Future<bool> stopOfflineRecording() async {
    if (_isMockMode) {
      _isOfflineRecording = false;
      _safeAdd(_offlineRecordingController, false);
      // Register a mock exercise entry for testing
      _mockStoredExercises.add(PolarExerciseEntry(
        path: '/exercises/mock_night_sleep_${DateTime.now().millisecondsSinceEpoch}',
        date: DateTime.now().subtract(const Duration(hours: 7, minutes: 30)),
        entryId: const Uuid().v4(),
      ));
      debugPrint('[BLE] [MOCK] Standalone offline recording stopped');
      return true;
    }

    if (_connectedDeviceId == null) {
      debugPrint('[BLE] Cannot stop recording: device not connected');
      return false;
    }

    try {
      await _polar.stopRecording(_connectedDeviceId!).timeout(const Duration(seconds: 8));
      _isOfflineRecording = false;
      _safeAdd(_offlineRecordingController, false);
      debugPrint('[BLE] Standalone offline recording stopped on $_connectedDeviceId');
      return true;
    } catch (e) {
      debugPrint('[BLE] Failed to stop offline recording: $e');
      return false;
    }
  }

  /// Executes a file-transfer session (listing, downloading) while pausing
  /// online PMD sensor streams (ACC/PPI/HR).
  ///
  /// Polar Verity Sense firmware strictly responds with SYSTEM_BUSY (202) if
  /// file transfer operations are attempted while PMD streaming is active.
  /// This session manager cleanly cancels active subscriptions, flushes the
  /// BLE queue, stops any active offline recording, executes the action,
  /// and safely restores online streaming afterwards.
  Future<T> withFileTransferSession<T>(Future<T> Function() action) async {
    if (_isMockMode) {
      return await action();
    }

    if (_connectedDeviceId == null) {
      debugPrint('[BLE PFTP] Device not connected, cannot start file transfer session');
      throw Exception('Device not connected');
    }

    // If already in an active file transfer session, execute directly to prevent nested stream toggling
    if (_isSyncingOffline) {
      return await action();
    }

    final deviceId = _connectedDeviceId!;
    final wasStreaming = _connectionState == BleConnectionState.streaming;
    _isSyncingOffline = true;
    _lastSyncError = null;
    _lastStorageDiagnostics = null;

    try {
      debugPrint('[BLE PFTP] Pausing online streams for file transfer on $deviceId...');
      await _cancelStreamsAsync();
      _updateState(BleConnectionState.connected);

      // 1. Allow 800ms for PMD STOP commands and in-flight notifications to drain completely
      await Future.delayed(const Duration(milliseconds: 800));

      // 2. If connected very recently, wait briefly (up to 3s) for PFTP feature readiness
      if (!_readyFeatures.contains(PolarSdkFeature.fileTransfer)) {
        for (int i = 0; i < 12; i++) {
          if (_connectedDeviceId != deviceId || _readyFeatures.contains(PolarSdkFeature.fileTransfer)) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 250));
        }
      }

      // 3. Check if the sensor has an ongoing SDK offline recording and finalize it
      try {
        final recStatus = await checkOfflineRecordingStatus();
        if (recStatus != null && recStatus.ongoing) {
          debugPrint('[BLE PFTP] Active recording detected (${recStatus.entryId}). Stopping recording before sync...');
          await stopOfflineRecording();
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      } catch (e) {
        debugPrint('[BLE PFTP] Non-fatal check/stop recording error: $e');
      }

      // 4. Execute the caller's action
      return await action();
    } finally {
      _isSyncingOffline = false;
      if (_connectedDeviceId == deviceId && wasStreaming) {
        debugPrint('[BLE PFTP] Resuming online sensor streams on $deviceId...');
        await Future.delayed(const Duration(milliseconds: 500));
        await _startSensorStreams(deviceId);
      }
    }
  }

  /// List all offline exercise entries stored in the sensor's 16MB flash memory
  Future<List<PolarExerciseEntry>> listOfflineRecordings() async {
    if (_isMockMode) {
      if (_mockStoredExercises.isEmpty) {
        _mockStoredExercises.add(PolarExerciseEntry(
          path: '/exercises/mock_overnight_sleep',
          date: DateTime.now().subtract(const Duration(hours: 8)),
          entryId: 'mock-overnight-sleep-entry',
        ));
      }
      return List.from(_mockStoredExercises);
    }

    if (_connectedDeviceId == null) {
      debugPrint('[BLE] Cannot list recordings: device not connected');
      _lastSyncError = 'Device not connected';
      return [];
    }

    if (!_isSyncingOffline) {
      return await withFileTransferSession(() => _listOfflineRecordingsInternal());
    } else {
      return await _listOfflineRecordingsInternal();
    }
  }

  Future<List<PolarExerciseEntry>> _listOfflineRecordingsInternal() async {
    final deviceId = _connectedDeviceId;
    if (deviceId == null) return [];

    try {
      debugPrint('[BLE PFTP] Requesting exercise & offline list from $deviceId...');
      final entries = await _polar.listExercises(deviceId).timeout(const Duration(seconds: 25));
      debugPrint('[BLE PFTP] Successfully found ${entries.length} offline recordings on $deviceId');
      if (entries.isEmpty) {
        try {
          _lastStorageDiagnostics = await _polar.inspectDeviceStorage(deviceId).timeout(const Duration(seconds: 15));
          debugPrint('[BLE PFTP] Empty list diagnostics: $_lastStorageDiagnostics');
        } catch (diagErr) {
          debugPrint('[BLE PFTP] Diagnostic inspect failed: $diagErr');
        }
      }
      return entries;
    } catch (e) {
      debugPrint('[BLE PFTP] Initial attempt to list exercises failed: $e, retrying after 1.5s...');
      await Future.delayed(const Duration(milliseconds: 1500));
      try {
        final entries = await _polar.listExercises(deviceId).timeout(const Duration(seconds: 25));
        debugPrint('[BLE PFTP] Retry found ${entries.length} offline recordings on $deviceId');
        return entries;
      } catch (e2) {
        debugPrint('[BLE PFTP] Error listing offline recordings after retry: $e2');
        _lastSyncError = e2.toString();
        try {
          _lastStorageDiagnostics = await _polar.inspectDeviceStorage(deviceId).timeout(const Duration(seconds: 15));
        } catch (_) {}
        return [];
      }
    }
  }

  /// Inspect internal flash storage and readiness flags on the connected device
  Future<Map<String, dynamic>> inspectDeviceStorage() async {
    if (_isMockMode) {
      return {
        'mockMode': true,
        'u0Paths': ['/U/0/mock/E/000000/00/SAMPLES.BPB'],
        'offlineEntries': [],
      };
    }
    if (_connectedDeviceId == null) {
      return {'error': 'Device not connected'};
    }
    return await withFileTransferSession(() async {
      final diag = await _polar.inspectDeviceStorage(_connectedDeviceId!).timeout(const Duration(seconds: 20));
      _lastStorageDiagnostics = diag;
      return diag;
    });
  }

  /// Download recorded exercise samples from sensor memory
  Future<PolarExerciseData?> fetchOfflineRecording(PolarExerciseEntry entry) async {
    if (_isMockMode || entry.entryId.startsWith('mock')) {
      debugPrint('[BLE] [MOCK] Fetching mock overnight exercise data');
      return generateMockSleepExerciseData();
    }

    if (_connectedDeviceId == null) {
      debugPrint('[BLE] Cannot fetch recording: device not connected');
      return null;
    }

    if (!_isSyncingOffline) {
      return await withFileTransferSession(() => _fetchOfflineRecordingInternal(entry));
    } else {
      return await _fetchOfflineRecordingInternal(entry);
    }
  }

  Future<PolarExerciseData?> _fetchOfflineRecordingInternal(PolarExerciseEntry entry) async {
    final deviceId = _connectedDeviceId;
    if (deviceId == null) return null;

    try {
      debugPrint('[BLE PFTP] Downloading exercise ${entry.entryId} (${entry.path}, date: ${entry.date})...');
      final data = await _polar.fetchExercise(deviceId, entry).timeout(const Duration(seconds: 90));
      debugPrint('[BLE PFTP] Successfully fetched exercise ${entry.entryId}: ${data.samples.length} samples, interval: ${data.interval}s');
      return data;
    } catch (e) {
      debugPrint('[BLE PFTP] Initial attempt to fetch exercise failed: $e, retrying after 2s...');
      await Future.delayed(const Duration(milliseconds: 2000));
      try {
        final data = await _polar.fetchExercise(deviceId, entry).timeout(const Duration(seconds: 90));
        debugPrint('[BLE PFTP] Retry successfully fetched exercise ${entry.entryId}: ${data.samples.length} samples');
        return data;
      } catch (e2) {
        debugPrint('[BLE PFTP] Error fetching exercise data after retry: $e2');
        _lastSyncError = e2.toString();
        return null;
      }
    }
  }

  /// Remove single exercise from sensor memory after syncing
  Future<bool> removeOfflineRecording(PolarExerciseEntry entry) async {
    if (_isMockMode || entry.entryId.startsWith('mock')) {
      _mockStoredExercises.removeWhere((e) => e.entryId == entry.entryId);
      debugPrint('[BLE] [MOCK] Removed mock exercise entry: ${entry.entryId}');
      return true;
    }

    if (_connectedDeviceId == null) return false;

    try {
      await _polar.removeExercise(_connectedDeviceId!, entry).timeout(const Duration(seconds: 6));
      debugPrint('[BLE] Removed exercise entry from $_connectedDeviceId: ${entry.entryId}');
      return true;
    } catch (e) {
      debugPrint('[BLE] Error removing exercise entry: $e');
      return false;
    }
  }

  /// Generates a scientifically modeled 7.5-hour overnight sleep session
  /// for Verity Sense testing without waiting 8 hours overnight.
  static PolarExerciseData generateMockSleepExerciseData() {
    final random = Random(42);
    final samples = <int>[];

    // Total duration: 450 minutes = 7.5 hours
    // Samples at 1 Hz = 27,000 samples
    // 30s epochs: 900 epochs
    for (int epoch = 0; epoch < 900; epoch++) {
      double targetMeanHr;
      double targetRmssd;

      if (epoch < 30 || epoch >= 860) {
        // Wake: elevated HR above baseline + 15 bpm
        targetMeanHr = 75.0 + random.nextDouble() * 6.0;
        targetRmssd = 26.0 + random.nextDouble() * 5.0;
      } else if ((epoch >= 150 && epoch < 300) || (epoch >= 480 && epoch < 600)) {
        // Deep Sleep: slow resting HR, elevated parasympathetic RMSSD
        targetMeanHr = 51.5 + sin(epoch * 0.05) * 2.0;
        targetRmssd = 56.0 + random.nextDouble() * 6.0;
      } else if ((epoch >= 300 && epoch < 370) || (epoch >= 600 && epoch < 720)) {
        // REM Sleep: autonomic bursts, higher variable HR, moderate RMSSD
        targetMeanHr = 66.0 + sin(epoch * 0.2) * 4.0;
        targetRmssd = 36.0 + random.nextDouble() * 4.0;
      } else {
        // Light Sleep: intermediate baseline HR <= 58 and normal RMSSD
        targetMeanHr = 56.5 + sin(epoch * 0.1) * 1.5;
        targetRmssd = 38.0 + random.nextDouble() * 4.0;
      }

      // Generate 30 1-second samples for this epoch
      final basePpi = 60000.0 / targetMeanHr;

      for (int s = 0; s < 30; s++) {
        // Direct successive difference matching target RMSSD
        final sign = s.isEven ? 1 : -1;
        final jitter = (random.nextDouble() - 0.5) * 3.0;
        final ppi = (basePpi + sign * (targetRmssd * 0.5) + jitter).round().clamp(500, 1500);
        samples.add(ppi);
      }
    }

    return PolarExerciseData(interval: 1, samples: samples);
  }

  void dispose() {
    _startupFallbackTimer?.cancel();
    _startupFallbackTimer = null;
    _batterySyncTimer?.cancel();
    _batterySyncTimer = null;
    _cancelStreams();
    _stopMockStreaming();
    _deviceConnectedSub?.cancel();
    _deviceConnectedSub = null;
    _deviceDisconnectedSub?.cancel();
    _deviceDisconnectedSub = null;
    _batterySub?.cancel();
    _batterySub = null;
    _batteryChargingSub?.cancel();
    _batteryChargingSub = null;
    _featuresReadinessSub?.cancel();
    _featuresReadinessSub = null;
    _featureReadySub?.cancel();
    _featureReadySub = null;
    _stateController.close();
    _discoveredDevicesController.close();
    _accStreamController.close();
    _ppiStreamController.close();
    _hrStreamController.close();
    _batteryStreamController.close();
    _chargingStreamController.close();
    _offlineRecordingController.close();
  }
}
