import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:timezone/timezone.dart' as tz;

import 'package:timezone/data/latest_all.dart' as tz;



class NotificationService {

  NotificationService();



  static const int _reminderId = 101;

  static const int _urgentId = 102;



  final FlutterLocalNotificationsPlugin _plugin =

      FlutterLocalNotificationsPlugin();



  Future<void> initialize() async {

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings);



    await _plugin

        .resolvePlatformSpecificImplementation<

            AndroidFlutterLocalNotificationsPlugin>()

        ?.requestNotificationsPermission();

  }



  Future<void> scheduleCheckInReminders(

    DateTime lastCheckIn,

    int timerDays,

  ) async {

    await _plugin.cancel(_reminderId);

    await _plugin.cancel(_urgentId);



    final base = lastCheckIn.toLocal();

    final expiry = base.add(Duration(days: timerDays));



    // Yellow warning at 66% remaining (34% elapsed)

    final yellowDay = (timerDays * 0.34).round().clamp(1, timerDays - 1);

    // Red warning at 33% remaining (67% elapsed)

    final redDay = (timerDays * 0.67).round().clamp(yellowDay + 1, timerDays - 1);



    await _scheduleIfBeforeExpiry(

      id: _reminderId,

      title: 'Reminder',

      body: 'Open Afterword to refresh your check-in timer.',

      scheduledFor: base.add(Duration(days: yellowDay)),

      expiry: expiry,

    );



    await _scheduleIfBeforeExpiry(

      id: _urgentId,

      title: 'URGENT',

      body: 'Your timer is almost up. Check in now.',

      scheduledFor: base.add(Duration(days: redDay)),

      expiry: expiry,

    );

  }



  Future<void> cancelAll() async {

    await _plugin.cancelAll();

  }



  Future<void> _scheduleIfBeforeExpiry({

    required int id,

    required String title,

    required String body,

    required DateTime scheduledFor,

    required DateTime expiry,

  }) async {

    if (!scheduledFor.isBefore(expiry)) return;



    const details = NotificationDetails(

      android: AndroidNotificationDetails(

        'afterword_checkin',

        'Check-in reminders',

        channelDescription: 'Reminders to check in before your timer expires.',

        importance: Importance.high,

        priority: Priority.high,

      ),

    );



    await _plugin.zonedSchedule(

      id,

      title,

      body,

      tz.TZDateTime.from(scheduledFor, tz.local),

      details,

      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,

      uiLocalNotificationDateInterpretation:

          UILocalNotificationDateInterpretation.absoluteTime,

    );

  }

}

