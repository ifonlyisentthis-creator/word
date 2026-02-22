-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  GRACE PERIOD AT 0 REMAINING — IMMEDIATE CLEANUP TRIGGER               ║
-- ║  Sets grace period to exactly 0 minutes remaining.                    ║
-- ║  Expected: Next heartbeat deletes sent entries, creates tombstones,    ║
-- ║  resets profile to fresh active state.                                 ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Step 1: Force ALL entries to 'sent' with expired sent_at (31 days ago)
UPDATE vault_entries
SET status  = 'sent',
    sent_at = now() - interval '31 days'
WHERE user_id = '9141d3aa-f0a1-4343-8403-aa52067661b7';

-- Step 2: Set profile to EXACTLY 30 days grace (0 minutes remaining)
UPDATE profiles
SET status               = 'inactive',
    protocol_executed_at  = now() - interval '30 days',
    warning_sent_at      = NULL,
    push_66_sent_at      = NULL,
    push_33_sent_at      = NULL
WHERE id = '9141d3aa-f0a1-4343-8403-aa52067661b7';
