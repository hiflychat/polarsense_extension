import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ble/polar_ble_manager.dart';
import 'sedentary_engine.dart';

final polarBleManagerProvider = Provider<PolarBleManager>((ref) {
  final manager = PolarBleManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

final bleConnectionStateProvider = StreamProvider<BleConnectionState>((ref) {
  final manager = ref.watch(polarBleManagerProvider);
  return manager.stateStream;
});

final sedentaryEngineProvider = Provider<SedentaryEngine>((ref) {
  final engine = SedentaryEngine();
  final bleManager = ref.watch(polarBleManagerProvider);

  // Automatically bind ACC stream
  engine.start(bleManager.accStream);

  // Sync initial connection status
  final initialConnected = bleManager.connectionState == BleConnectionState.connected ||
      bleManager.connectionState == BleConnectionState.streaming;
  engine.isDeviceConnected = initialConnected;

  // Reactively track BLE connection changes
  final stateSub = bleManager.stateStream.listen((state) {
    final connected = state == BleConnectionState.connected ||
        state == BleConnectionState.streaming;
    engine.isDeviceConnected = connected;
  });

  ref.onDispose(() {
    stateSub.cancel();
    engine.dispose();
  });

  return engine;
});

class SedentaryStateNotifier extends StateNotifier<SedentaryStatus> {
  final SedentaryEngine _engine;
  StreamSubscription<SedentaryStatus>? _statusSub;

  SedentaryStateNotifier(this._engine) : super(_engine.currentStatus) {
    _statusSub = _engine.statusStream.listen((status) {
      state = status;
    });
  }

  void setThreshold(int minutes) {
    _engine.alertThresholdMinutes = minutes;
    state = _engine.currentStatus;
  }

  void resetTimer() {
    _engine.resetManually();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }
}

final sedentaryStatusProvider =
    StateNotifierProvider<SedentaryStateNotifier, SedentaryStatus>((ref) {
  final engine = ref.watch(sedentaryEngineProvider);
  return SedentaryStateNotifier(engine);
});
