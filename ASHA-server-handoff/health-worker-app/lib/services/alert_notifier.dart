import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Raises notifications on THIS phone. Nothing here needs internet: the urgent list is worked out from the phone's own data.
abstract class AlertNotifier {
  Future<void> init();

  /// Asks Android 13+ for the notification permission. Returns whether alerts can be shown.
  Future<bool> requestPermission();

  /// Whether Android currently lets this app show notifications (a dropped notification must never be counted as delivered).
  Future<bool> canShow();

  /// Shows one notification now. Same [id] replaces the earlier one.
  Future<void> show({
    required int id,
    required String title,
    required String body,
  });

  /// A repeating morning reminder (08:00 India time) that fires even when the app is closed and there is no network.
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
  });
  Future<void> cancel(int id);
}

class PlatformAlertNotifier implements AlertNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'urgent_households',
      'Urgent households',
      channelDescription: 'Households that need attention first',
      importance: Importance.high,
      priority: Priority.high,
      // the lock screen shows only the generic title: household IDs stay private until the phone is unlocked
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
  );

  @override
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // iOS asks for permission only when we call requestPermission (after onboarding), not at start-up
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  /// Whether the phone currently lets this app show notifications (a dropped notification must never be counted as delivered).
  @override
  Future<bool> canShow() async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) return (await ios.checkPermissions())?.isEnabled ?? false;
    return false;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details,
    );
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    final ist = tz.getLocation(
      'Asia/Kolkata',
    ); // the app is for India; avoids a device-timezone plugin
    final now = tz.TZDateTime.now(ist);
    var at = tz.TZDateTime(ist, now.year, now.month, now.day, 8);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: at,
        notificationDetails: _details,
        // inexact: no special "exact alarm" permission is needed, and a few minutes either way does not matter here
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } on Object catch (e) {
      debugPrint('alerts: could not schedule the daily reminder: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id: id);
  }
}

/// For tests and platforms without notifications. Records what would have been shown.
class FakeAlertNotifier implements AlertNotifier {
  FakeAlertNotifier({this.permission = true});
  bool permission;
  final shown = <(int, String, String)>[];
  final daily = <(int, String, String)>[];
  final cancelled = <int>[];
  int permissionRequests = 0;
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<bool> canShow() async => permission;
  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async => shown.add((id, title, body));
  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
  }) async => daily.add((id, title, body));
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}
