import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:polar/polar.dart';
import '../../core/ble/polar_constants.dart';
import '../../core/database/health_database.dart';
import '../../core/database/models/sedentary_event.dart';
import '../../core/notifications/notification_service.dart';

enum PostureState {
  sedentary,     // Motionless sitting (< 0.035g)
  typingDesk,    // Desk keyboard/mouse work (0.035g - 0.070g, sitting stationary at desk)
  activeArmMove, // Active arm movement (0.070g - 0.150g, washing hair, stretching, chores -> breaks sedentary!)
  activeWalking, // Locomotion / walking (>= 0.150g -> breaks sedentary!)
}

class SedentaryStatus {
  final int sedentarySeconds;
  final int activeWalkingSeconds;
  final double currentVmu;
  final PostureState state;
  final int alertThresholdMinutes;
  final bool hasTriggeredAlert;
  final bool isDeviceConnected;
  final int walkingPauseGraceCounter;

  SedentaryStatus({
    required this.sedentarySeconds,
    required this.activeWalkingSeconds,
    required this.currentVmu,
    required this.state,
    required this.alertThresholdMinutes,
    required this.hasTriggeredAlert,
    this.isDeviceConnected = true,
    this.walkingPauseGraceCounter = 0,
  });

  bool get isActiveState =>
      state == PostureState.activeWalking || state == PostureState.activeArmMove;

  bool get isWalkingGraceActive =>
      activeWalkingSeconds > 0 &&
      walkingPauseGraceCounter > 0 &&
      !isActiveState;

  int get sedentaryMinutes => sedentarySeconds ~/ 60;
  int get sedentaryRemainingSeconds => sedentarySeconds % 60;

  String get formattedDuration {
    final mins = sedentaryMinutes.toString().padLeft(2, '0');
    final secs = sedentaryRemainingSeconds.toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  double get progressToAlert => (sedentarySeconds / (alertThresholdMinutes * 60)).clamp(0.0, 1.0);
  double get walkingResetProgress =>
      (activeWalkingSeconds / SedentaryEngine.activeResetRequirementSec.toDouble()).clamp(0.0, 1.0);
}

class SedentaryEngine {
  final HealthDatabase _database = HealthDatabase();
  final NotificationService _notifications = NotificationService();

  static const double sedentaryVmuThreshold = 0.035; // < 0.035g: motionless sitting
  static const double deskTypingVmuThreshold = 0.070; // 0.035g - 0.070g: desk keyboard/mouse work
  static const double activeArmVmuThreshold = 0.150;  // 0.070g - 0.150g: active arm movement (hair washing, chores, stretching)
  // >= 0.150g: active walking / stepping locomotion

  static const int activeResetRequirementSec = 60;   // 60 seconds of continuous active movement breaks sedentary spell
  static const int walkingPauseGraceSec = 15;        // 15 seconds pause tolerance during active breaks

  int _alertThresholdMinutes = 45;
  int get alertThresholdMinutes => _alertThresholdMinutes;
  set alertThresholdMinutes(int value) {
    if (_alertThresholdMinutes != value) {
      _alertThresholdMinutes = value;
      _database.setSetting('sedentary_threshold_minutes', value.toString());
      _emitStatus();
    }
  }

  SedentaryEngine() {
    _loadPersistedThreshold();
  }

  Future<void> _loadPersistedThreshold() async {
    try {
      final saved = await _database.getSetting('sedentary_threshold_minutes');
      if (saved != null) {
        final parsed = int.tryParse(saved);
        if (parsed != null && parsed >= 15 && parsed <= 180) {
          _alertThresholdMinutes = parsed;
          _emitStatus();
        }
      }
    } catch (e) {
      debugPrint('[SedentaryEngine] Failed to load threshold: $e');
    }
  }

  final List<double> _vmuWindowBuffer = [];
  DateTime? _windowStartTime;
  static const Duration _windowDuration = Duration(seconds: 5);

  int _sedentarySeconds = 0;
  int _activeWalkingSeconds = 0;
  int _walkingPauseGraceCounter = 0;
  int get walkingPauseGraceCounter => _walkingPauseGraceCounter;

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
    walkingPauseGraceCounter: _walkingPauseGraceCounter,
  );

  void start(Stream<PolarAccData> accStream) {
    stop();
    _sedentaryPeriodStart = DateTime.now();
    _windowStartTime = DateTime.now();
    _vmuWindowBuffer.clear();

    _accSubscription = accStream.listen(
      _processAccData,
      onError: (err) {
        debugPrint('[SedentaryEngine] ACC stream error: $err');
      },
      cancelOnError: false,
    );

    // Continuous 1-second ticker for real-time live seconds progression
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      try {
        if (_isDeviceConnected) {
          final isStationaryOrTyping = _currentState == PostureState.sedentary ||
              _currentState == PostureState.typingDesk;

          final isActiveMovement = _currentState == PostureState.activeWalking ||
              _currentState == PostureState.activeArmMove;

          if (isStationaryOrTyping) {
            // Desk typing (MET 1.3-1.5) and motionless sitting accumulate sedentary duration
            _sedentarySeconds++;
            _checkAlertCondition();

            // Handle active movement grace countdown during brief pauses
            if (_activeWalkingSeconds > 0) {
              if (_walkingPauseGraceCounter > 0) {
                _walkingPauseGraceCounter--;
              } else {
                _activeWalkingSeconds = 0;
              }
            }
          } else if (isActiveMovement) {
            // User is actively moving (walking, washing hair, stretching, household chores):
            // 1. Sedentary accumulation PAUSES completely!
            // 2. Active movement streak increments
            _activeWalkingSeconds++;
            _walkingPauseGraceCounter = walkingPauseGraceSec;
            if (_activeWalkingSeconds >= activeResetRequirementSec) {
              _handleWalkingReset();
            }
          }
          _emitStatus();
        }
      } catch (e) {
        debugPrint('[SedentaryEngine] Ticker error: $e');
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

    // Safety buffer limit: prevent unbounded memory growth if timestamp jumps
    if (_vmuWindowBuffer.length > 600) {
      _vmuWindowBuffer.removeRange(0, _vmuWindowBuffer.length - 300);
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
      // Motionless sitting (< 0.035g)
      _currentState = PostureState.sedentary;
      // Note: do not instantly zero _activeWalkingSeconds; ticker counts down the 15s grace period
    } else if (windowMeanVmu < deskTypingVmuThreshold) {
      // Desk keyboard typing / mouse operations (0.035g - 0.070g)
      _currentState = PostureState.typingDesk;
    } else if (windowMeanVmu < activeArmVmuThreshold) {
      // Active arm movement: washing hair, stretching, household chores (0.070g - 0.150g)
      _currentState = PostureState.activeArmMove;
      _walkingPauseGraceCounter = walkingPauseGraceSec; // Refresh grace window
    } else {
      // Active walking / locomotion (>= 0.150g)
      _currentState = PostureState.activeWalking;
      _walkingPauseGraceCounter = walkingPauseGraceSec; // Refresh grace window
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
    _walkingPauseGraceCounter = 0;
    _hasTriggeredAlert = false;
    _sedentaryPeriodStart = now;

    _notifications.showWalkingGoalAchieved();
  }

  void resetManually() {
    _sedentarySeconds = 0;
    _activeWalkingSeconds = 0;
    _walkingPauseGraceCounter = 0;
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
