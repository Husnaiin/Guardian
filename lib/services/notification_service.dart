import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Callback for when notification is tapped
  Function(String?)? onNotificationTapped;
  
  // Callback for action buttons
  Function(String action, String? payload)? onActionSelected;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap or action button
        if (response.notificationResponseType == NotificationResponseType.selectedNotificationAction) {
          // Action button clicked
          if (onActionSelected != null) {
            onActionSelected!(response.actionId!, response.payload);
          }
        } else {
          // Notification body tapped
          if (response.payload != null && onNotificationTapped != null) {
            onNotificationTapped!(response.payload);
          }
        }
      },
    );

    // Request permissions for iOS
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    // Request permissions for Android 13+
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  Future<void> showFireAlert({
    required double x,
    required double y,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'fire_alerts',
      'Fire Alerts',
      channelDescription: 'Notifications for detected fires',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Fire Detected',
      icon: '@mipmap/ic_launcher',
      color: Colors.deepOrange,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        'Fire detected at location X: ${x.toStringAsFixed(2)}, Y: ${y.toStringAsFixed(2)}',
      ),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'accept',
          'Accept & Suppress',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'reject',
          'Reject',
          cancelNotification: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
      'Fire Alert!',
      'Fire at X: ${x.toStringAsFixed(2)}, Y: ${y.toStringAsFixed(2)}',
      notificationDetails,
      payload: '$x,$y', // Pass coordinates as payload
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }
}

