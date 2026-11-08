import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  static const String sedentaryChannelId = 'polarsense_sedentary_channel';
  static const String sedentaryChannelName = 'Sedentary Alerts';
  static const String sedentaryChannelDesc = 'Reminders to stand up and move when sitting too long';

  static const String sleepChannelId = 'polarsense_sleep_channel';
  static const String sleepChannelName = 'Sleep & Recovery';
  static const String sleepChannelDesc = 'Morning sleep summaries and recovery insights';

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Use clean vector drawable for notifications (prevents Adaptive Icon XML crash)
      const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      await _createNotificationChannels();
      _isInitialized = true;
      debugPrint('[Notifications] Initialized successfully');
    } catch (e) {
      debugPrint('[Notifications] Failed to initialize: $e');
    }
  }

  Future<void> _createNotificationChannels() async {
    try {
      final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            sedentaryChannelId,
            sedentaryChannelName,
            description: sedentaryChannelDesc,
            importance: Importance.max,
            enableVibration: true,
            playSound: true,
          ),
        );

        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            sleepChannelId,
            sleepChannelName,
            description: sleepChannelDesc,
            importance: Importance.high,
            enableVibration: false,
            playSound: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('[Notifications] Error creating channels: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('[Notifications] User tapped notification: ${response.payload}');
  }

  Future<void> showSedentaryAlert({required int minutesStationary}) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        sedentaryChannelId,
        sedentaryChannelName,
        channelDescription: sedentaryChannelDesc,
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        icon: 'ic_notification',
        category: AndroidNotificationCategory.reminder,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        1001,
        'Time to move! 🚶‍♂️',
        "You've been stationary for $minutesStationary minutes. Stretch your legs or walk for 90 seconds.",
        notificationDetails,
        payload: 'sedentary_alert',
      );
    } catch (e) {
      debugPrint('[Notifications] Error showing sedentary alert: $e');
    }
  }

  Future<void> showWalkingGoalAchieved() async {
    try {
      const androidDetails = AndroidNotificationDetails(
        sedentaryChannelId,
        sedentaryChannelName,
        channelDescription: sedentaryChannelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: 'ic_notification',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: false,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        1002,
        'Great job! Activity detected ✨',
        'Sedentary timer reset after active movement.',
        notificationDetails,
        payload: 'walking_reset',
      );
    } catch (e) {
      debugPrint('[Notifications] Error showing walking goal: $e');
    }
  }

  Future<void> showSleepSummary({
    required int recoveryScore,
    required double durationHours,
    required int deepPercent,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        sleepChannelId,
        sleepChannelName,
        channelDescription: sleepChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        2001,
        'Morning Recovery Score: $recoveryScore / 100 🌙',
        'Slept ${durationHours.toStringAsFixed(1)} hrs with $deepPercent% deep sleep. Check your full breakdown.',
        notificationDetails,
        payload: 'sleep_summary',
      );
    } catch (e) {
      debugPrint('[Notifications] Error showing sleep summary: $e');
    }
  }
}
