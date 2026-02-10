import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushService {
  PushService({
    required SupabaseClient client,
    FirebaseMessaging? messaging,
    FlutterSecureStorage? storage,
  })  : _client = client,
        _messaging = messaging ?? FirebaseMessaging.instance,
        _storage = storage ?? const FlutterSecureStorage();

  static const String _tokenStorageKey = 'afterword_fcm_token';

  final SupabaseClient _client;
  final FirebaseMessaging _messaging;
  final FlutterSecureStorage _storage;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  bool _initialized = false;
  String? _currentUserId;

  Future<void> initialize() async {
    if (!_isSupportedPlatform()) return;
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(settings);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    _onMessageSubscription = FirebaseMessaging.onMessage.listen(
      (message) async {
        final notification = message.notification;
        if (notification == null) return;

        const androidDetails = AndroidNotificationDetails(
          'afterword_push',
          'Afterword alerts',
          channelDescription: 'Remote notifications from Afterword.',
          importance: Importance.high,
          priority: Priority.high,
        );

        await _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(android: androidDetails),
        );
      },
    );

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      (token) async {
        await _storage.write(key: _tokenStorageKey, value: token);
        if (_currentUserId != null) {
          await _upsertToken(userId: _currentUserId!, token: token);
        }
      },
    );

    _initialized = true;
  }

  Future<void> onSignIn(String userId) async {
    if (!_isSupportedPlatform()) return;
    _currentUserId = userId;
    await initialize();

    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;

      await _storage.write(key: _tokenStorageKey, value: token);
      await _upsertToken(userId: userId, token: token);
    } catch (e) {
      debugPrint('PushService.onSignIn: FCM token fetch failed: $e');
    }
  }

  Future<void> onSignOut() async {
    final token = await _storage.read(key: _tokenStorageKey);
    _currentUserId = null;

    if (token != null && token.isNotEmpty) {
      try {
        if (_client.auth.currentUser != null) {
          await _client.from('push_devices').delete().eq('fcm_token', token);
        }
      } catch (_) {
      }
    }

    await _storage.delete(key: _tokenStorageKey);
  }

  Future<void> _upsertToken({required String userId, required String token}) async {
    final platform = _platformName();

    await _client.from('push_devices').upsert(
      {
        'user_id': userId,
        'fcm_token': token,
        'platform': platform,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'fcm_token',
    );
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  bool _isSupportedPlatform() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> dispose() async {
    await _onMessageSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
  }
}
