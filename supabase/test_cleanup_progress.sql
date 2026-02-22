-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  TEST "CLEANUP IN PROGRESS" STATE                                      ║
-- ║  This will make the app show "Cleanup in progress" immediately.        ║
-- ║  Expected: App shows "Cleanup in progress" → heartbeat deletes entries   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Step 1: Mark all entries as sent (they were already sent when timer expired)
UPDATE vault_entries
SET status  = 'sent',
    sent_at = now() - interval '31 days'
WHERE user_id = '9141d3aa-f0a1-4343-8403-aa52067661b7';

-- Step 2: Set grace period to exactly 30 days ago (triggers cleanup)
UPDATE profiles
SET status               = 'inactive',
    protocol_executed_at  = now() - interval '30 days',
    warning_sent_at      = NULL,
    push_66_sent_at      = NULL,
    push_33_sent_at      = NULL
WHERE id = '9141d3aa-f0a1-4343-8403-aa52067661b7';
