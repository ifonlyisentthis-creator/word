import 'package:flutter_local_notifications/flutter_local_notifications.dart';



class NotificationService {

  NotificationService();



  static const int _reminderId = 101;

  static const int _urgentId = 102;



  final FlutterLocalNotificationsPlugin _plugin =

      FlutterLocalNotificationsPlugin();



  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings: settings);



    await _plugin

        .resolvePlatformSpecificImplementation<

            AndroidFlutterLocalNotificationsPlugin>()

        ?.requestNotificationsPermission();

  }



  Future<void> scheduleCheckInReminders(

    DateTime lastCheckIn,

    int timerDays, {

    DateTime? push66SentAt,

    DateTime? push33SentAt,

  }) async {

    // Reminder timing is server-authoritative (UTC) via automation/heartbeat.py.

    // Keep this method as a cleanup shim so legacy scheduled local reminders are

    // removed after app updates.

    await _plugin.cancel(id: _reminderId);

    await _plugin.cancel(id: _urgentId);

  }



  Future<void> cancelAll() async {

    await _plugin.cancelAll();

  }

}

