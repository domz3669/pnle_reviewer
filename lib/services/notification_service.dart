import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const int dailySessionsReadyId = 1001;
  static const int adCapsRefilledId = 1002;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(settings);

    tz.initializeTimeZones();
    try {
      final timezoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (e) {
      debugPrint('Notification timezone fallback to default: $e');
    }

    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    await initialize();

    var granted = true;

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      final iosGranted = await iosImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      granted = granted && (iosGranted ?? false);
    }

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final androidGranted = await androidImpl.requestNotificationsPermission();
      granted = granted && (androidGranted ?? true);
    }

    return granted;
  }

  Future<void> scheduleDailySessionsReady({
    int hour = 5,
    int minute = 30,
  }) async {
    await initialize();

    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      dailySessionsReadyId,
      'Sessions Ready',
      'Your 4 daily sessions are now available. Time to review.',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_sessions_ready',
          'Daily Sessions Ready',
          channelDescription: 'Daily reminder for session reset',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'daily_sessions_ready',
    );
  }

  Future<void> scheduleAdCapsRefilled(DateTime when) async {
    await initialize();

    final now = DateTime.now();
    if (!when.isAfter(now)) {
      await cancelAdCapsRefilled();
      return;
    }

    final scheduled = tz.TZDateTime.from(when, tz.local);
    await _plugin.zonedSchedule(
      adCapsRefilledId,
      'Ad Chances Refilled',
      'Your Watch Ad for +1 Session chances are full again.',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'ad_caps_refilled',
          'Ad Chances Refilled',
          channelDescription: 'Alerts when ad bonus chances are full again',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'ad_caps_refilled',
    );
  }

  Future<void> cancelAdCapsRefilled() async {
    await initialize();
    await _plugin.cancel(adCapsRefilledId);
  }

  Future<void> cancelAllManaged() async {
    await initialize();
    await _plugin.cancel(dailySessionsReadyId);
    await _plugin.cancel(adCapsRefilledId);
  }
}
