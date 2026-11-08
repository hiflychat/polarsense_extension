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

  final _offlineRecordingController = StreamController<bool>.broadcast();
  Stream<bool> get offlineRecordingStream => _offlineRecordingController.stream;

  bool _isOfflineRecording = false;
  bool get isOfflineRecording => _isOfflineRecording;

  final List<PolarExerciseEntry> _mockStoredExercises = [];
  List<PolarExerciseEntry> get mockStoredExercises => List.unmodifiable(_mockStoredExercises);

  final Map<String, DiscoveredDevice> _discoveredDevices = {};

  int? _batteryLevel;
  int? get batteryLevel => _batteryLevel;

  int? _currentHr;
  int? get currentHr => _currentHr;

  StreamSubscription? _deviceConnectedSub;
  StreamSubscription? _deviceDisconnectedSub;
  StreamSubscription? _batterySub;
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
      _updateState(BleConnectionState.connected);
      _reconnectAttempts = 0;

      // Remember device
      final name = _discoveredDevices[info.deviceId]?.name ?? _pairedDeviceName ?? 'Polar Verity Sense';
      savePairedDevice(info.deviceId, name);

      // Safety fallback: if feature readiness callback is delayed, start streams after GATT stabilizes
      Future.delayed(const Duration(milliseconds: 3500), () {
        if (_connectedDeviceId == info.deviceId && _connectionState == BleConnectionState.connected) {
          debugPrint('[BLE] Feature readiness timeout fallback -> starting sensor streams');
          _startSensorStreams(info.deviceId);
        }
      });
    });

    _deviceDisconnectedSub = _polar.deviceDisconnected.listen((event) {
      debugPrint('[BLE] Device disconnected: ${event.info.deviceId}');
      _updateState(BleConnectionState.disconnected);
      _connectedDeviceId = null;
      _batteryLevel = null;
      _currentHr = null;
      _isOfflineRecording = false;
      _isStartingStreams = false;
      _offlineRecordingController.add(false);
      _cancelStreams();

      if (!_intentionalDisconnect) {
        _attemptAutoReconnect(event.info.deviceId);
      }
    });

    _batterySub = _polar.batteryLevel.listen((event) {
      debugPrint('[BLE] Real battery level received: ${event.level}%');
      _batteryLevel = event.level;
      _batteryStreamController.add(event.level);
    });

    _featuresReadinessSub = _polar.sdkFeaturesReadiness.listen((event) {
      debugPrint('[BLE] SDK Features readiness: ${event.ready} for ${event.identifier}');
      if (event.identifier == _connectedDeviceId &&
          event.ready.contains(PolarSdkFeature.onlineStreaming)) {
        _startSensorStreams(event.identifier);
      }
    });

    _featureReadySub = _polar.sdkFeatureReady.listen((event) {
      debugPrint('[BLE] SDK Feature ready: ${event.feature} on ${event.identifier}');
      if (event.identifier == _connectedDeviceId &&
          event.feature == PolarSdkFeature.onlineStreaming) {
        _startSensorStreams(event.identifier);
      }
    });
  }

  Future<void> _loadPairedDeviceAndAutoConnect() async {
    try {
      _pairedDeviceId = await _database.getSetting('paired_device_id');
      _pairedDeviceName = await _database.getSetting('paired_device_name');
      debugPrint('[BLE] Loaded paired device: $_pairedDeviceId ($_pairedDeviceName)');

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
    _stateController.add(state);
  }

  void enableMockMode(bool enable) {
    if (_isMockMode == enable) return;
    _isMockMode = enable;
    if (enable) {
      disconnect();
      _connectedDeviceId = 'POLAR-MOCK-7A99';
      _batteryLevel = 90;
      _currentHr = 72;
      _updateState(BleConnectionState.connected);
      _startMockStreaming();
    } else {
      _stopMockStreaming();
      _connectedDeviceId = null;
      _batteryLevel = null;
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
      _discoveredDevicesController.add(_discoveredDevices.values.toList());
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
    _updateState(BleConnectionState.scanning);

    try {
      final searchSub = _polar.searchForDevice().listen(
        (deviceInfo) {
          _discoveredDevices[deviceInfo.deviceId] = DiscoveredDevice(
            deviceId: deviceInfo.deviceId,
            name: deviceInfo.name.isNotEmpty ? deviceInfo.name : 'Polar Verity Sense',
            rssi: deviceInfo.rssi,
            isConnectable: deviceInfo.isConnectable,
          );
          _discoveredDevicesController.add(_discoveredDevices.values.toList());
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
      await _polar.connectToDevice(deviceId);
      return true;
    } catch (e) {
      debugPrint('[BLE] Connection error: $e');
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
      _currentHr = null;
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
    _batteryLevel = null;
    _currentHr = null;
    _isStartingStreams = false;
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
        final hasPerms = await hasBlePermissions();
        if (hasPerms) {
          debugPrint('[BLE] Auto-reconnecting to $deviceId...');
          await connectToDevice(deviceId);
        }
      }
    });
  }

  Future<void> _startSensorStreams(String deviceId) async {
    if (_isStartingStreams || _connectedDeviceId != deviceId) return;
    _isStartingStreams = true;

    try {
      debugPrint('[BLE] Querying available online streams for $deviceId');
      Set<PolarDataType> availableTypes = {};
      try {
        availableTypes = await _polar.getAvailableOnlineStreamDataTypes(deviceId);
        debugPrint('[BLE] Available types: $availableTypes');
      } catch (e) {
        debugPrint('[BLE] getAvailableOnlineStreamDataTypes fallback: $e');
        availableTypes = {PolarDataType.hr, PolarDataType.ppi, PolarDataType.acc};
      }

      // 1. Heart Rate Stream (Optical HR & standard BLE HR)
      if (availableTypes.contains(PolarDataType.hr) && _hrSub == null) {
        try {
          debugPrint('[BLE] Starting HR stream for $deviceId');
          _hrSub = _polar.startHrStreaming(deviceId).listen(
            (hrData) {
              for (final sample in hrData.samples) {
                if (sample.hr > 0) {
                  _currentHr = sample.hr;
                  _hrStreamController.add(sample.hr);
                }
              }
            },
            onError: (err) {
              debugPrint('[BLE] HR stream error: $err');
              _hrSub?.cancel();
              _hrSub = null;
            },
          );
        } catch (e) {
          debugPrint('[BLE] Error starting HR stream: $e');
          _hrSub = null;
        }
      }

      // 2. Optical Heart Rate PPI Stream (Pulse-to-Pulse intervals with instantaneous HR)
      if (availableTypes.contains(PolarDataType.ppi) && _ppiSub == null) {
        try {
          debugPrint('[BLE] Starting PPI stream for $deviceId');
          _ppiSub = _polar.startPpiStreaming(deviceId).listen(
            (ppiData) {
              _ppiStreamController.add(ppiData);
              for (final sample in ppiData.samples) {
                if (sample.hr > 0) {
                  _currentHr = sample.hr;
                  _hrStreamController.add(sample.hr);
                }
              }
            },
            onError: (err) {
              debugPrint('[BLE] PPI stream error: $err');
              _ppiSub?.cancel();
              _ppiSub = null;
            },
          );
        } catch (e) {
          debugPrint('[BLE] Error starting PPI stream: $e');
          _ppiSub = null;
        }
      }

      // 3. Accelerometer Stream (Automatic device capability negotiation)
      if (availableTypes.contains(PolarDataType.acc) && _accSub == null) {
        try {
          debugPrint('[BLE] Requesting ACC settings for $deviceId');
          final settings = await _polar.requestStreamSettings(deviceId, PolarDataType.acc);
          final maxSettings = settings.maxSettings();
          debugPrint('[BLE] Starting ACC with maxSettings: ${maxSettings.settings}');

          _accSub = _polar.startAccStreaming(deviceId, settings: maxSettings).listen(
            (data) {
              _accStreamController.add(data);
            },
            onError: (err) {
              debugPrint('[BLE] Auto ACC error: $err, falling back to explicit 52Hz');
              _accSub?.cancel();
              _accSub = null;
              _startDefaultAccStream(deviceId);
            },
          );
        } catch (e) {
          debugPrint('[BLE] Error getting ACC settings: $e, falling back to explicit 52Hz');
          _startDefaultAccStream(deviceId);
        }
      }

      _updateState(BleConnectionState.streaming);
    } catch (e) {
      debugPrint('[BLE] Error in _startSensorStreams: $e');
    } finally {
      _isStartingStreams = false;
    }
  }

  void _startDefaultAccStream(String deviceId) {
    if (_accSub != null) return;
    try {
      debugPrint('[BLE] Starting explicit 52Hz ACC stream for $deviceId');
      _accSub = _polar.startAccStreaming(
        deviceId,
        settings: PolarSensorSetting({
          PolarSettingType.sampleRate: 52, // Native Polar Verity Sense rate
          PolarSettingType.range: 8,
        }),
      ).listen(
        (data) => _accStreamController.add(data),
        onError: (err) {
          debugPrint('[BLE] ACC default 52Hz stream error: $err');
          _accSub?.cancel();
          _accSub = null;
        },
      );
    } catch (e) {
      debugPrint('[BLE] Error starting default ACC stream: $e');
      _accSub = null;
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
      _accStreamController.add(PolarAccData(samples: samples));
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
      _ppiStreamController.add(PolarPpiData(samples: [sample]));
      final hr = (60000 / ppiMs).round();
      _currentHr = hr;
      _hrStreamController.add(hr);
    });

    _mockHrTimer?.cancel();
    _mockHrTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final b = 88 + random.nextInt(10);
      _batteryLevel = b;
      _batteryStreamController.add(b);
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
      _offlineRecordingController.add(_isOfflineRecording);
      return status;
    }

    if (_connectedDeviceId == null) return null;

    try {
      final status = await _polar.requestRecordingStatus(_connectedDeviceId!);
      _isOfflineRecording = status.ongoing;
      _offlineRecordingController.add(status.ongoing);
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
      _offlineRecordingController.add(true);
      debugPrint('[BLE] [MOCK] Standalone offline recording started');
      return true;
    }

    if (_connectedDeviceId == null) {
      debugPrint('[BLE] Cannot start recording: device not connected');
      return false;
    }

    try {
      final exerciseId = const Uuid().v4();
      await _polar.startRecording(
        _connectedDeviceId!,
        exerciseId: exerciseId,
        interval: interval,
        sampleType: sampleType,
      );
      _isOfflineRecording = true;
      _offlineRecordingController.add(true);
      debugPrint('[BLE] Standalone offline recording started on $_connectedDeviceId (id: $exerciseId)');
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
      _offlineRecordingController.add(false);
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
      await _polar.stopRecording(_connectedDeviceId!);
      _isOfflineRecording = false;
      _offlineRecordingController.add(false);
      debugPrint('[BLE] Standalone offline recording stopped on $_connectedDeviceId');
      return true;
    } catch (e) {
      debugPrint('[BLE] Failed to stop offline recording: $e');
      return false;
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
      return [];
    }

    try {
      final entries = await _polar.listExercises(_connectedDeviceId!);
      debugPrint('[BLE] Found ${entries.length} offline recordings on $_connectedDeviceId');
      return entries;
    } catch (e) {
      debugPrint('[BLE] Error listing offline recordings: $e');
      return [];
    }
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

    try {
      final data = await _polar.fetchExercise(_connectedDeviceId!, entry);
      debugPrint('[BLE] Fetched exercise: ${data.samples.length} samples, interval: ${data.interval}s');
      return data;
    } catch (e) {
      debugPrint('[BLE] Error fetching exercise data: $e');
      return null;
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
      await _polar.removeExercise(_connectedDeviceId!, entry);
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
    _cancelStreams();
    _stopMockStreaming();
    _deviceConnectedSub?.cancel();
    _deviceDisconnectedSub?.cancel();
    _batterySub?.cancel();
    _featuresReadinessSub?.cancel();
    _featureReadySub?.cancel();
    _stateController.close();
    _discoveredDevicesController.close();
    _accStreamController.close();
    _ppiStreamController.close();
    _hrStreamController.close();
    _batteryStreamController.close();
    _offlineRecordingController.close();
  }
}
