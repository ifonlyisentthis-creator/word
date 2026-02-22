-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  TEST 0 MINUTES REMAINING — TIMER & GRACE                               ║
-- ║  Run each section independently. After each, run heartbeat.           ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  1. TIMER AT 0 MINUTES REMAINING                                        ║
-- ║  Expected: Next heartbeat sends all vault entries to recipients,       ║
-- ║  marks profile inactive (grace period starts).                         ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

UPDATE profiles
SET last_check_in     = now() - (timer_days || ' days')::interval - interval '1 minute',
    warning_sent_at   = NULL,
    push_66_sent_at   = NULL,
    push_33_sent_at   = NULL
WHERE id = '9141d3aa-f0a1-4343-8403-aa52067661b7';

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  2. GRACE AT 0 MINUTES REMAINING                                       ║
-- ║  Run AFTER Section 1 + heartbeat (entries are already marked as sent). ║
-- ║  Expected: Next heartbeat deletes ALL sent entries immediately,        ║
-- ║  creates tombstones, resets profile to fresh active state.             ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Just set grace period to expired (entries are already 'sent' from Section 1)
UPDATE profiles
SET status               = 'inactive',
    protocol_executed_at  = now() - interval '30 days',
    warning_sent_at      = NULL,
    push_66_sent_at      = NULL,
    push_33_sent_at      = NULL
WHERE id = '9141d3aa-f0a1-4343-8403-aa52067661b7';

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  3. RESET TO FRESH STATE (after testing)                                 ║
-- ║  Returns everything to clean active state.                              ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Reset all entries to active
UPDATE vault_entries
SET status  = 'active',
    sent_at = NULL
WHERE user_id = '9141d3aa-f0a1-4343-8403-aa52067661b7';

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
WHERE id = '9141d3aa-f0a1-4343-8403-aa52067661b7';

-- Delete any tombstones from previous tests
DELETE FROM vault_entry_tombstones
WHERE user_id = '9141d3aa-f0a1-4343-8403-aa52067661b7';
