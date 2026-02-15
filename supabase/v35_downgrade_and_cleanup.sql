-- ============================================================================
-- AFTERWORD v35 — Subscription Downgrade Support + Bot Cleanup
-- Run this in Supabase SQL Editor.
--
-- Changes:
--   1. Grant service_role UPDATE on additional profile columns needed by
--      heartbeat.py subscription downgrade handler (timer_days, last_check_in,
--      selected_theme, selected_soul_fire).
--   2. No new tables or functions needed — heartbeat.py handles all logic.
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  1. Extend service_role column-level grants for downgrade handling     ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- The heartbeat.py subscription downgrade handler needs to reset:
--   timer_days, last_check_in, selected_theme, selected_soul_fire
-- in addition to the already-granted:
--   subscription_status, status, warning_sent_at, push_66_sent_at, push_33_sent_at

GRANT UPDATE (
  timer_days,
  last_check_in,
  selected_theme,
  selected_soul_fire
) ON profiles TO service_role;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  2. Verify existing grants are still in place                         ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Ensure the previously granted columns are still accessible
GRANT UPDATE (
  subscription_status,
  status,
  warning_sent_at,
  push_66_sent_at,
  push_33_sent_at
) ON profiles TO service_role;

-- Authenticated users can still only update hmac_key_encrypted directly
-- (all other mutations go through SECURITY DEFINER RPCs)
GRANT UPDATE (hmac_key_encrypted) ON profiles TO authenticated;

-- ============================================================================
-- END OF v35 SQL
-- ============================================================================
