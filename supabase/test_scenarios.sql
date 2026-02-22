-- ============================================================================
-- AFTERWORD — TEST SCENARIO SQL SCRIPTS
-- ============================================================================
-- Replace YOUR_USER_ID with your actual profile UUID before running.
-- Run each scenario independently. After each, run heartbeat and observe.
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SCENARIO 1: TIMER EXPIRED — 0 MINUTES REMAINING                      ║
-- ║  Expected: Next heartbeat sends all vault entries to recipients,       ║
-- ║  marks profile inactive (grace period starts).                         ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

UPDATE profiles
SET last_check_in     = now() - (timer_days || ' days')::interval - interval '1 minute',
    warning_sent_at   = NULL,
    push_66_sent_at   = NULL,
    push_33_sent_at   = NULL
WHERE id = 'YOUR_USER_ID';

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SCENARIO 2: GRACE PERIOD EXPIRED — 0 MINUTES REMAINING               ║
-- ║  Simulates the FULL lifecycle: entries sent, grace ended, cleanup.     ║
-- ║  Expected: Next heartbeat deletes sent entries, creates tombstones,    ║
-- ║  resets profile to fresh active state.                                 ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Step 1: Force ALL entries to 'sent' with expired sent_at (no status filter!)
UPDATE vault_entries
SET status  = 'sent',
    sent_at = now() - interval '31 days'
WHERE user_id = 'YOUR_USER_ID';

-- Step 2: Set profile to expired grace period
UPDATE profiles
SET status               = 'inactive',
    protocol_executed_at  = now() - interval '31 days',
    warning_sent_at      = NULL,
    push_66_sent_at      = NULL,
    push_33_sent_at      = NULL
WHERE id = 'YOUR_USER_ID';

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SCENARIO 3: GRACE PERIOD ACTIVE — 15 DAYS REMAINING                  ║
-- ║  Expected: App shows "Cleanup in progress" with countdown.             ║
-- ║  Entries are still accessible to recipients. No heartbeat action yet.  ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Step 1: Mark entries as sent (recently)
UPDATE vault_entries
SET status  = 'sent',
    sent_at = now() - interval '15 days'
WHERE user_id = 'YOUR_USER_ID';

-- Step 2: Set profile to active grace (15 days in)
UPDATE profiles
SET status               = 'inactive',
    protocol_executed_at  = now() - interval '15 days',
    warning_sent_at      = NULL,
    push_66_sent_at      = NULL,
    push_33_sent_at      = NULL
WHERE id = 'YOUR_USER_ID';

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SCENARIO 4: ORPHANED INACTIVE — NO protocol_executed_at              ║
-- ║  Simulates a stuck state where profile is inactive but missing the    ║
-- ║  protocol_executed_at timestamp (should never happen, but guard test).║
-- ║  Expected: heal_inconsistent_profiles Guard 2 resets to active.       ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

UPDATE profiles
SET status               = 'inactive',
    protocol_executed_at  = NULL,
    warning_sent_at      = NULL,
    push_66_sent_at      = NULL,
    push_33_sent_at      = NULL
WHERE id = 'YOUR_USER_ID';

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SCENARIO 5: STALE ACTIVE — protocol_executed_at set but active       ║
-- ║  Simulates a stuck state where profile is active but has a stale      ║
-- ║  protocol_executed_at (should have been cleared).                      ║
-- ║  Expected: heal_inconsistent_profiles Guard 1 clears the field.       ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

UPDATE profiles
SET status               = 'active',
    protocol_executed_at  = now() - interval '5 days'
WHERE id = 'YOUR_USER_ID';

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SCENARIO 6: GRACE EXPIRED WITH UNPROCESSED ENTRIES                   ║
-- ║  Simulates partial failure: grace expired but some entries are still   ║
-- ║  'active' (never got sent). Tests Scenario B of grace reset.          ║
-- ║  Expected: Profile re-activated with expired timer, entries processed  ║
-- ║  on the SAME heartbeat run.                                           ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Step 1: Ensure entries are 'active' (unsent)
UPDATE vault_entries
SET status  = 'active',
    sent_at = NULL
WHERE user_id = 'YOUR_USER_ID';

-- Step 2: Set profile to expired grace
UPDATE profiles
SET status               = 'inactive',
    protocol_executed_at  = now() - interval '31 days',
    warning_sent_at      = NULL,
    push_66_sent_at      = NULL,
    push_33_sent_at      = NULL
WHERE id = 'YOUR_USER_ID';

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SCENARIO 7: PUSH NOTIFICATION AT 66% REMAINING                       ║
-- ║  Expected: Next heartbeat sends the 66% push notification.            ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

UPDATE profiles
SET last_check_in     = now() - (timer_days * 0.4 || ' days')::interval,
    warning_sent_at   = NULL,
    push_66_sent_at   = NULL,
    push_33_sent_at   = NULL
WHERE id = 'YOUR_USER_ID';

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SCENARIO 8: PUSH NOTIFICATION AT 33% REMAINING                       ║
-- ║  Expected: Next heartbeat sends the 33% push notification.            ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

UPDATE profiles
SET last_check_in     = now() - (timer_days * 0.72 || ' days')::interval,
    warning_sent_at   = NULL,
    push_66_sent_at   = now() - interval '1 day',  -- 66% already sent
    push_33_sent_at   = NULL
WHERE id = 'YOUR_USER_ID';

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SCENARIO 9: STALE SENDING LOCK                                       ║
-- ║  Simulates an entry stuck in 'sending' status (crashed mid-send).     ║
-- ║  Expected: requeue_stale_sending_entries reverts it to 'active'.      ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

UPDATE vault_entries
SET status     = 'sending',
    updated_at = now() - interval '45 minutes'
WHERE user_id = 'YOUR_USER_ID'
  AND status = 'active'
LIMIT 1;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SCENARIO 10: FRESH RESET — Return to clean state after testing       ║
-- ║  Resets profile AND entries to a fresh, active state.                  ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Reset all entries to active
UPDATE vault_entries
SET status  = 'active',
    sent_at = NULL
WHERE user_id = 'YOUR_USER_ID';

-- Reset profile to fresh active
UPDATE profiles
SET status               = 'active',
    timer_days           = 30,
    last_check_in        = now(),
    protocol_executed_at  = NULL,
    warning_sent_at      = NULL,
    push_66_sent_at      = NULL,
    push_33_sent_at      = NULL,
    last_entry_at        = NULL
WHERE id = 'YOUR_USER_ID';

-- Delete any tombstones from previous tests
DELETE FROM vault_entry_tombstones
WHERE user_id = 'YOUR_USER_ID';
