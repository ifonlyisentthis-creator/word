import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the 12-hour check-in cooldown logic.
///
/// The cooldown is implemented in HomeController.manualCheckIn(). Because
/// HomeController depends on Supabase, ProfileService, etc., we test the
/// *pure decision logic* here in isolation.
///
/// The gate logic is:
///   needsWrite = timerExpired || (serverCooldownOk && sessionCooldownOk)
///
///   serverCooldownOk = lastCheckIn == null
///       || now - lastCheckIn >= 12 hours
///
///   sessionCooldownOk = lastWriteAt == null
///       || now - lastWriteAt >= 12 hours

const _cooldown = Duration(hours: 12);

/// Pure replica of the decision gate from HomeController.manualCheckIn().
bool shouldWrite({
  required DateTime now,
  DateTime? serverLastCheckIn,
  DateTime? sessionLastWriteAt,
  required bool timerExpired,
}) {
  final serverCooldownOk = serverLastCheckIn == null ||
      now.difference(serverLastCheckIn) >= _cooldown;

  final sessionCooldownOk = sessionLastWriteAt == null ||
      now.difference(sessionLastWriteAt) >= _cooldown;

  return timerExpired || (serverCooldownOk && sessionCooldownOk);
}

void main() {
  group('Check-in cooldown gate', () {
    final now = DateTime(2026, 2, 21, 12, 0);

    test('brand-new account (null lastCheckIn) always writes', () {
      expect(
        shouldWrite(
          now: now,
          serverLastCheckIn: null,
          sessionLastWriteAt: null,
          timerExpired: false,
        ),
        isTrue,
      );
    });

    test('first press in a new session (null sessionLastWriteAt) writes if server cooldown ok', () {
      final thirteenHoursAgo = now.subtract(const Duration(hours: 13));
      expect(
        shouldWrite(
          now: now,
          serverLastCheckIn: thirteenHoursAgo,
          sessionLastWriteAt: null,
          timerExpired: false,
        ),
        isTrue,
      );
    });

    test('skips write when server check-in is recent (< 12h)', () {
      final fiveHoursAgo = now.subtract(const Duration(hours: 5));
      expect(
        shouldWrite(
          now: now,
          serverLastCheckIn: fiveHoursAgo,
          sessionLastWriteAt: fiveHoursAgo,
          timerExpired: false,
        ),
        isFalse,
      );
    });

    test('skips write when session write is recent even if server is stale', () {
      final thirteenHoursAgo = now.subtract(const Duration(hours: 13));
      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      expect(
        shouldWrite(
          now: now,
          serverLastCheckIn: thirteenHoursAgo,
          sessionLastWriteAt: twoHoursAgo,
          timerExpired: false,
        ),
        isFalse,
      );
    });

    test('writes when both server and session cooldowns have elapsed', () {
      final thirteenHoursAgo = now.subtract(const Duration(hours: 13));
      expect(
        shouldWrite(
          now: now,
          serverLastCheckIn: thirteenHoursAgo,
          sessionLastWriteAt: thirteenHoursAgo,
          timerExpired: false,
        ),
        isTrue,
      );
    });

    test('writes exactly at 12-hour boundary', () {
      final exactlyTwelveHoursAgo = now.subtract(const Duration(hours: 12));
      expect(
        shouldWrite(
          now: now,
          serverLastCheckIn: exactlyTwelveHoursAgo,
          sessionLastWriteAt: exactlyTwelveHoursAgo,
          timerExpired: false,
        ),
        isTrue,
      );
    });

    test('does NOT write at 11h 59m (just under cooldown)', () {
      final justUnder = now.subtract(const Duration(hours: 11, minutes: 59));
      expect(
        shouldWrite(
          now: now,
          serverLastCheckIn: justUnder,
          sessionLastWriteAt: justUnder,
          timerExpired: false,
        ),
        isFalse,
      );
    });

    test('safety valve: expired timer always writes regardless of cooldown', () {
      final oneHourAgo = now.subtract(const Duration(hours: 1));
      expect(
        shouldWrite(
          now: now,
          serverLastCheckIn: oneHourAgo,
          sessionLastWriteAt: oneHourAgo,
          timerExpired: true,
        ),
        isTrue,
      );
    });

    test('safety valve: expired timer with null timestamps writes', () {
      expect(
        shouldWrite(
          now: now,
          serverLastCheckIn: null,
          sessionLastWriteAt: null,
          timerExpired: true,
        ),
        isTrue,
      );
    });

    test('rapid spam within same session is blocked', () {
      // Simulate: first press writes (sessionLastWriteAt is set to now)
      // Subsequent presses are within cooldown
      final firstWriteAt = now;
      for (int seconds = 1; seconds <= 60; seconds++) {
        final spamTime = now.add(Duration(seconds: seconds));
        expect(
          shouldWrite(
            now: spamTime,
            serverLastCheckIn: firstWriteAt,
            sessionLastWriteAt: firstWriteAt,
            timerExpired: false,
          ),
          isFalse,
          reason: 'Press $seconds seconds after first write should be blocked',
        );
      }
    });

    test('different account gets fresh cooldown (null session)', () {
      // When switching accounts, the controller is recreated — sessionLastWriteAt
      // is null, and serverLastCheckIn comes from the new account's profile.
      final thirteenHoursAgo = now.subtract(const Duration(hours: 13));
      expect(
        shouldWrite(
          now: now,
          serverLastCheckIn: thirteenHoursAgo,
          sessionLastWriteAt: null, // fresh controller
          timerExpired: false,
        ),
        isTrue,
      );
    });
  });
}
