import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:polar/polar.dart';
import '../../core/ble/polar_constants.dart';
import '../../core/database/health_database.dart';
import '../../core/database/models/sedentary_event.dart';
import '../../core/notifications/notification_service.dart';

enum PostureState {
  sedentary,
  intermediate,
  activeWalking,
}

class SedentaryStatus {
  final int sedentarySeconds;
  final int activeWalkingSeconds;
  final double currentVmu;
  final PostureState state;
  final int alertThresholdMinutes;
  final bool hasTriggeredAlert;
  final bool isDeviceConnected;

  SedentaryStatus({
    required this.sedentarySeconds,
    required this.activeWalkingSeconds,
    required this.currentVmu,
    required this.state,
    required this.alertThresholdMinutes,
    required this.hasTriggeredAlert,
    this.isDeviceConnected = true,
  });

  int get sedentaryMinutes => sedentarySeconds ~/ 60;
  int get sedentaryRemainingSeconds => sedentarySeconds % 60;

  String get formattedDuration {
    final mins = sedentaryMinutes.toString().padLeft(2, '0');
    final secs = sedentaryRemainingSeconds.toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  double get progressToAlert => (sedentarySeconds / (alertThresholdMinutes * 60)).clamp(0.0, 1.0);
  double get walkingResetProgress => (activeWalkingSeconds / 90.0).clamp(0.0, 1.0);
}

class SedentaryEngine {
  final HealthDatabase _database = HealthDatabase();
  final NotificationService _notifications = NotificationService();

  int _alertThresholdMinutes = 45;
  int get alertThresholdMinutes => _alertThresholdMinutes;
  set alertThresholdMinutes(int value) {
    _alertThresholdMinutes = value;
  }

  static const double sedentaryVmuThreshold = 0.04; // < 0.04g
  static const double walkingVmuThreshold = 0.15;   // >= 0.15g
  static const int walkingResetRequirementSec = 90; // 90 seconds continuous walking

  final List<double> _vmuWindowBuffer = [];
  DateTime? _windowStartTime;
  static const Duration _windowDuration = Duration(seconds: 5);

  int _sedentarySeconds = 0;
  int _activeWalkingSeconds = 0;
  double _lastWindowVmu = 0.0;
  PostureState _currentState = PostureState.sedentary;
  bool _hasTriggeredAlert = false;
  bool _isDeviceConnected = false;
  bool get isDeviceConnected => _isDeviceConnected;
  set isDeviceConnected(bool value) {
    if (_isDeviceConnected != value) {
      _isDeviceConnected = value;
      _emitStatus();
    }
  }

  DateTime? _sedentaryPeriodStart;
  DateTime? _lastAlertTime;

  StreamSubscription<PolarAccData>? _accSubscription;
  Timer? _ticker;
  final _statusController = StreamController<SedentaryStatus>.broadcast();
  Stream<SedentaryStatus> get statusStream => _statusController.stream;

  SedentaryStatus get currentStatus => SedentaryStatus(
    sedentarySeconds: _sedentarySeconds,
    activeWalkingSeconds: _activeWalkingSeconds,
    currentVmu: _lastWindowVmu,
    state: _currentState,
    alertThresholdMinutes: _alertThresholdMinutes,
    hasTriggeredAlert: _hasTriggeredAlert,
    isDeviceConnected: _isDeviceConnected,
  );

  void start(Stream<PolarAccData> accStream) {
    stop();
    _sedentaryPeriodStart = DateTime.now();
    _windowStartTime = DateTime.now();
    _vmuWindowBuffer.clear();

    _accSubscription = accStream.listen(_processAccData);

    // Continuous 1-second ticker for real-time live seconds progression
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDeviceConnected) {
        if (_currentState == PostureState.sedentary) {
          _sedentarySeconds++;
          _checkAlertCondition();
        } else if (_currentState == PostureState.activeWalking) {
          _activeWalkingSeconds++;
          if (_activeWalkingSeconds >= walkingResetRequirementSec) {
            _handleWalkingReset();
          }
        }
        _emitStatus();
      }
    });

    _emitStatus();
  }

  void stop() {
    _accSubscription?.cancel();
    _accSubscription = null;
    _ticker?.cancel();
    _ticker = null;
    _vmuWindowBuffer.clear();
  }

  /// Calculates Vector Magnitude Unit (VMU) for a sample in G:
  /// VMU = | sqrt(x^2 + y^2 + z^2) - 1.0g |
  static double calculateVmu(int rawX, int rawY, int rawZ) {
    final x = rawX * PolarConstants.mgToG;
    final y = rawY * PolarConstants.mgToG;
    final z = rawZ * PolarConstants.mgToG;

    final magnitude = sqrt(x * x + y * y + z * z);
    return (magnitude - 1.0).abs();
  }

  void _processAccData(PolarAccData data) {
    for (final sample in data.samples) {
      final vmu = calculateVmu(sample.x, sample.y, sample.z);
      _vmuWindowBuffer.add(vmu);
    }

    final now = DateTime.now();
    _windowStartTime ??= now;

    if (now.difference(_windowStartTime!) >= _windowDuration && _vmuWindowBuffer.isNotEmpty) {
      _evaluateWindow();
      _vmuWindowBuffer.clear();
      _windowStartTime = now;
      _emitStatus();
    }
  }

  /// Evaluates sliding 5-second window VMU mean and updates state machine
  void _evaluateWindow() {
    final windowMeanVmu = _vmuWindowBuffer.reduce((a, b) => a + b) / _vmuWindowBuffer.length;
    _lastWindowVmu = windowMeanVmu;

    if (windowMeanVmu < sedentaryVmuThreshold) {
      // Sedentary state
      _currentState = PostureState.sedentary;
      _activeWalkingSeconds = 0; // Reset active continuous counter
    } else if (windowMeanVmu >= walkingVmuThreshold) {
      // Active / Walking state
      _currentState = PostureState.activeWalking;
    } else {
      // Intermediate state (e.g. minor arm movements/typing)
      _currentState = PostureState.intermediate;
      _activeWalkingSeconds = 0;
    }
  }

  void _checkAlertCondition() {
    final thresholdSeconds = _alertThresholdMinutes * 60;
    if (_sedentarySeconds >= thresholdSeconds) {
      final now = DateTime.now();
      // Only fire alert if never fired or last alert was more than 10 minutes ago
      if (!_hasTriggeredAlert ||
          (_lastAlertTime != null && now.difference(_lastAlertTime!).inMinutes >= 10)) {
        _hasTriggeredAlert = true;
        _lastAlertTime = now;
        _notifications.showSedentaryAlert(minutesStationary: _sedentarySeconds ~/ 60);
      }
    }
  }

  void _handleWalkingReset() {
    final now = DateTime.now();
    final sedentaryMinutes = _sedentarySeconds ~/ 60;

    // Log the completed sedentary period to local database
    if (sedentaryMinutes > 0 && _sedentaryPeriodStart != null) {
      _database.insertSedentaryEvent(
        SedentaryEvent(
          startTime: _sedentaryPeriodStart!,
          endTime: now,
          durationMinutes: sedentaryMinutes,
          triggeredAlert: _hasTriggeredAlert,
          resolvedByWalking: true,
        ),
      );
    }

    // Reset timers
    _sedentarySeconds = 0;
    _activeWalkingSeconds = 0;
    _hasTriggeredAlert = false;
    _sedentaryPeriodStart = now;

    _notifications.showWalkingGoalAchieved();
  }

  void resetManually() {
    _sedentarySeconds = 0;
    _activeWalkingSeconds = 0;
    _hasTriggeredAlert = false;
    _sedentaryPeriodStart = DateTime.now();
    _emitStatus();
  }

  void _emitStatus() {
    if (!_statusController.isClosed) {
      _statusController.add(currentStatus);
    }
  }

  void dispose() {
    stop();
    _statusController.close();
  }
}
