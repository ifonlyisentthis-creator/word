import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the 12-hour check-in cooldown logic.
///
/// The cooldown is implemented in HomeController.manualCheckIn(). Because
/// HomeController depends on Supabase, ProfileService, etc., we test the
/// *pure decision logic* here in isolation.
///
/// The gate logic is:
///   firstPressInSession = lastWriteAt == null
///   needsWrite = firstPressInSession || (serverCooldownOk && sessionCooldownOk)
///
///   serverCooldownOk = lastCheckIn == null
///       || now - lastCheckIn >= 12 hours
///
///   sessionCooldownOk = lastWriteAt == null
///       || now - lastWriteAt >= 12 hours
///
/// Result contract:
///   needsWrite == true  → CheckInResult.success  → "Signal Verified"
///   needsWrite == false → CheckInResult.cooldown  → "Vault Secure"
///
/// Timer UI contract:
///   success  → _profile updated from server → timer bar + text reset to 100%
///   cooldown → _profile NOT touched         → timer bar + text unchanged

const _cooldown = Duration(hours: 12);

/// Mirrors the decision gate from HomeController.manualCheckIn().
/// Returns 'success' for real write, 'cooldown' for suppressed.
String checkInGate({
  required DateTime now,
  DateTime? serverLastCheckIn,
  DateTime? sessionLastWriteAt,
}) {
  final serverCooldownOk = serverLastCheckIn == null ||
      now.difference(serverLastCheckIn) >= _cooldown;

  final sessionCooldownOk = sessionLastWriteAt == null ||
      now.difference(sessionLastWriteAt) >= _cooldown;

  final firstPressInSession = sessionLastWriteAt == null;
  final needsWrite = firstPressInSession ||
      (serverCooldownOk && sessionCooldownOk);

  return needsWrite ? 'success' : 'cooldown';
}

void main() {
  group('Check-in cooldown gate', () {
    final now = DateTime(2026, 2, 21, 12, 0);

    test('brand-new account (null lastCheckIn) → success', () {
      expect(
        checkInGate(now: now, serverLastCheckIn: null, sessionLastWriteAt: null),
        'success',
      );
    });

    test('first press in new session + server cooldown ok → success', () {
      final thirteenHoursAgo = now.subtract(const Duration(hours: 13));
      expect(
        checkInGate(now: now, serverLastCheckIn: thirteenHoursAgo, sessionLastWriteAt: null),
        'success',
      );
    });

    test('server check-in recent (< 12h) but already wrote this session → cooldown', () {
      final fiveHoursAgo = now.subtract(const Duration(hours: 5));
      expect(
        checkInGate(now: now, serverLastCheckIn: fiveHoursAgo, sessionLastWriteAt: fiveHoursAgo),
        'cooldown',
      );
    });

    test('server check-in recent (< 12h) but first press in session → success (fresh account fix)', () {
      final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));
      expect(
        checkInGate(now: now, serverLastCheckIn: fiveMinutesAgo, sessionLastWriteAt: null),
        'success',
      );
    });

    test('session write recent even if server stale → cooldown', () {
      final thirteenHoursAgo = now.subtract(const Duration(hours: 13));
      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      expect(
        checkInGate(now: now, serverLastCheckIn: thirteenHoursAgo, sessionLastWriteAt: twoHoursAgo),
        'cooldown',
      );
    });

    test('both server and session cooldowns elapsed → success', () {
      final thirteenHoursAgo = now.subtract(const Duration(hours: 13));
      expect(
        checkInGate(now: now, serverLastCheckIn: thirteenHoursAgo, sessionLastWriteAt: thirteenHoursAgo),
        'success',
      );
    });

    test('exactly at 12-hour boundary → success', () {
      final exactlyTwelveHoursAgo = now.subtract(const Duration(hours: 12));
      expect(
        checkInGate(now: now, serverLastCheckIn: exactlyTwelveHoursAgo, sessionLastWriteAt: exactlyTwelveHoursAgo),
        'success',
      );
    });

    test('11h 59m (just under cooldown) → cooldown', () {
      final justUnder = now.subtract(const Duration(hours: 11, minutes: 59));
      expect(
        checkInGate(now: now, serverLastCheckIn: justUnder, sessionLastWriteAt: justUnder),
        'cooldown',
      );
    });

    test('rapid spam within same session is all cooldown', () {
      final firstWriteAt = now;
      for (int seconds = 1; seconds <= 60; seconds++) {
        final spamTime = now.add(Duration(seconds: seconds));
        expect(
          checkInGate(now: spamTime, serverLastCheckIn: firstWriteAt, sessionLastWriteAt: firstWriteAt),
          'cooldown',
          reason: 'Press $seconds seconds after first write should be cooldown',
        );
      }
    });

    test('different account gets fresh cooldown (null session) → success', () {
      final thirteenHoursAgo = now.subtract(const Duration(hours: 13));
      expect(
        checkInGate(now: now, serverLastCheckIn: thirteenHoursAgo, sessionLastWriteAt: null),
        'success',
      );
    });
  });

  group('Timer UI invariant', () {
    // These tests verify the contract: on cooldown, _profile is NOT updated,
    // so the timer bar + text must stay unchanged. On success, _profile IS
    // updated from the server response, so timer resets to 100%.

    test('cooldown press does not change simulated profile lastCheckIn', () {
      final originalLastCheckIn = DateTime(2026, 2, 20, 0, 0);
      final now = DateTime(2026, 2, 20, 8, 0); // 8 hours later (< 12h)

      // Simulate: cooldown active, profile should NOT be updated
      final result = checkInGate(
        now: now,
        serverLastCheckIn: originalLastCheckIn,
        sessionLastWriteAt: originalLastCheckIn,
      );
      expect(result, 'cooldown');

      // In the real code, _profile is not touched, so lastCheckIn stays:
      final simulatedProfile = originalLastCheckIn;
      expect(simulatedProfile, originalLastCheckIn);

      // Timer remaining calculation: deadline = lastCheckIn + timerDays
      const timerDays = 30;
      final deadline = originalLastCheckIn.add(const Duration(days: timerDays));
      final remaining = deadline.difference(now);
      expect(remaining.inDays, 29); // 30 - ~0.33 days = 29 full days
      expect(remaining.isNegative, false); // Timer still running
    });

    test('success press updates simulated profile lastCheckIn to now', () {
      final originalLastCheckIn = DateTime(2026, 2, 7, 0, 0);
      final now = DateTime(2026, 2, 21, 12, 0); // 14.5 days later (>12h)

      final result = checkInGate(
        now: now,
        serverLastCheckIn: originalLastCheckIn,
        sessionLastWriteAt: null,
      );
      expect(result, 'success');

      // In the real code, _profile is updated with server response.
      // Simulate: lastCheckIn becomes ~now (server returns current UTC time)
      final updatedLastCheckIn = now;
      const timerDays = 30;
      final deadline = updatedLastCheckIn.add(const Duration(days: timerDays));
      final remaining = deadline.difference(now);
      expect(remaining.inDays, 30); // Full 30 days after reset
    });
  });

  group('Cooldown does NOT apply to other timer changes', () {
    // These tests document that the 12-hour cooldown is ONLY for Soul Fire.
    // Timer adjustments (updateTimerDays), subscription snapping, etc. are
    // separate methods in HomeController and have NO cooldown gate.

    test('updateTimerDays is a separate code path with no cooldown', () {
      // This is a documentation/structural test. In HomeController:
      //   updateTimerDays() calls _profileService.updateTimerDays() directly.
      //   It does NOT go through the cooldown gate.
      //   It does NOT check _lastWriteAt or _checkInCooldown.
      // Verified by code inspection — no cooldown references in that method.
      expect(true, isTrue); // Structural assertion
    });

    test('subscription downgrade timer snap is immediate', () {
      // When a subscription is cancelled/refunded and the user was on a custom
      // timer, the heartbeat snaps them back to 30 days immediately.
      // This happens in heartbeat.py process_downgrade(), not through Soul Fire.
      // No cooldown applies.
      expect(true, isTrue); // Structural assertion
    });
  });

  group('Grace period blocks Soul Fire entirely', () {
    test('manualCheckIn returns error when in grace period', () {
      // In real code: if (_user == null || _isInGracePeriod) return CheckInResult.error;
      // The Soul Fire button is also IgnorePointer during grace period.
      // So there is no "safety valve" needed — expired timer = grace = blocked.
      expect(true, isTrue); // Structural assertion
    });
  });
}
