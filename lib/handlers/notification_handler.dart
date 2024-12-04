import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:patrol_challenge/handlers/permission_handler.dart';
import 'package:patrol_challenge/ui/style/colors.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationHandler {
  NotificationHandler(
    this._flutterLocalNotificationsPlugin,
  );

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;

  Future<void> init(VoidCallback onNotificationTap) async {
    await _init(onNotificationTap);
  }

  Future<void> _init(VoidCallback onNotificationTap) async {
    await _flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('notification_icon'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (_) => onNotificationTap(),
    );
  }

  Future<bool> _requestPermission() async {
    final permissionStatus = await PermissionHandler.requestPermissions();
    return switch (permissionStatus) {
      PermissionStatus.granted => true,
      _ => false,
    };
  }

  Future<void> triggerLocalNotification({
    required VoidCallback onPressed,
    required VoidCallback onError,
  }) async {
    final hasPermission = await _requestPermission();
    if (!hasPermission) {
      onError();
      return;
    }
    await _init(onPressed);
    await _showNotification(title: 'Tap me to finish the quiz!');
  }

  Future<void> _showNotification({
    required String title,
    String? body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'patrolChallengeChannelId',
        'patrolChallengeChannel',
        importance: Importance.max,
        priority: Priority.high,
        color: PTColors.lcBlack,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.active,
      ),
    );

    return _flutterLocalNotificationsPlugin.show(0, title, body, details);
  }
}
