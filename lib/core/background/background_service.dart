import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(PolarBackgroundTaskHandler());
}

class PolarBackgroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BackgroundTaskHandler] Foreground task started at $timestamp');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Periodic heartbeat to keep process healthy
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[BackgroundTaskHandler] Foreground task destroyed at $timestamp');
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}
}

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  Future<void> initialize() async {
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'polarsense_foreground_service',
          channelName: 'PolarSense Live Tracker',
          channelDescription: 'Maintains continuous Bluetooth connection with Polar Verity Sense.',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(5000),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: false,
        ),
      );
    } catch (e) {
      debugPrint('[BackgroundService] Failed to initialize: $e');
    }
  }

  Future<bool> startService() async {
    if (!Platform.isAndroid) {
      // iOS relies on native CoreBluetooth UIBackgroundModes bluetooth-central
      _isRunning = true;
      return true;
    }

    if (await FlutterForegroundTask.isRunningService) {
      _isRunning = true;
      return true;
    }

    try {
      final receivePort = FlutterForegroundTask.receivePort;
      receivePort?.listen((message) {
        debugPrint('[BackgroundService] Received message: $message');
      });

      final serviceRequest = await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'PolarSense Active Monitoring',
        notificationText: 'Tracking sedentary posture & sensor signals in real-time',
        notificationIcon: const NotificationIcon(
          metaDataName: 'com.polarsense.extension.NOTIFICATION_ICON',
        ),
        callback: startCallback,
      );

      _isRunning = serviceRequest is ServiceRequestSuccess;
      return _isRunning;
    } catch (e) {
      debugPrint('[BackgroundService] Error starting foreground service: $e');
      return false;
    }
  }

  Future<bool> stopService() async {
    if (!Platform.isAndroid) {
      _isRunning = false;
      return true;
    }

    final serviceRequest = await FlutterForegroundTask.stopService();
    _isRunning = !(serviceRequest is ServiceRequestSuccess);
    return !_isRunning;
  }
}
