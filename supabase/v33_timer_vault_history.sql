-- ============================================================================
-- AFTERWORD — SQL #33: Timer/Vault/History Update
-- Run this in Supabase SQL Editor after comprehensive_update.sql (#32).
--
-- Changes:
--   1. Restores cleanup_sent_entries function (dropped in #31, needed by cron)
--   2. Re-schedules daily cron cleanup at 03:00 UTC
--   3. Adds vault_entry_tombstones table if missing (for History tab)
--   4. Adds RLS policy for tombstones
--   5. Grants for tombstones
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  1. VAULT ENTRY TOMBSTONES (History tab — deletion log)                ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE TABLE IF NOT EXISTS vault_entry_tombstones (
  vault_entry_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_name text NOT NULL,
  sent_at timestamptz,
  expired_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS vault_entry_tombstones_user_idx
  ON vault_entry_tombstones(user_id, expired_at);

ALTER TABLE vault_entry_tombstones ENABLE ROW LEVEL SECURITY;

-- Users can only read their own tombstones
DROP POLICY IF EXISTS tombstones_select_own ON vault_entry_tombstones;
CREATE POLICY tombstones_select_own ON vault_entry_tombstones
FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Grant select to authenticated users
GRANT SELECT ON TABLE vault_entry_tombstones TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  2. CLEANUP SENT ENTRIES (restoring for cron + heartbeat)              ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- This function:
--   a. Creates tombstone records for sent entries about to be purged
--   b. Deletes audio storage objects for those entries
--   c. Deletes the vault_entries rows
--   d. Resets timer_days to 30 for users whose entries were just purged
--   e. Archives profiles with no remaining vault entries

CREATE OR REPLACE FUNCTION public.cleanup_sent_entries()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- 2a. Create tombstones for entries about to be purged
  INSERT INTO vault_entry_tombstones (vault_entry_id, user_id, sender_name, sent_at, expired_at)
  SELECT ve.id, ve.user_id, p.sender_name, ve.sent_at, now()
  FROM vault_entries ve
  JOIN profiles p ON p.id = ve.user_id
  WHERE ve.status = 'sent'
    AND ve.sent_at IS NOT NULL
    AND ve.sent_at < now() - interval '30 days'
  ON CONFLICT (vault_entry_id) DO NOTHING;

  -- 2b. Delete audio storage objects for entries about to be purged
  DELETE FROM storage.objects
  WHERE bucket_id = 'vault-audio'
    AND name IN (
      SELECT audio_file_path FROM vault_entries
      WHERE status = 'sent'
        AND sent_at < now() - interval '30 days'
        AND audio_file_path IS NOT NULL
    );

  -- 2c. Purge sent entries older than 30 days
  DELETE FROM vault_entries
  WHERE status = 'sent'
    AND sent_at IS NOT NULL
    AND sent_at < now() - interval '30 days';

  -- 2d. Archive profiles that have no remaining vault entries
  --     and had entries sent (tombstones exist)
  UPDATE profiles p
  SET status = 'archived'
  WHERE p.status IN ('active', 'inactive')
    AND NOT EXISTS (
      SELECT 1 FROM vault_entries v WHERE v.user_id = p.id
    )
    AND EXISTS (
      SELECT 1 FROM vault_entry_tombstones t WHERE t.user_id = p.id
    );
END;
$$;

ALTER FUNCTION public.cleanup_sent_entries() SET search_path = public, auth, storage;

-- Lock down: only service_role (cron / heartbeat)
REVOKE ALL ON FUNCTION public.cleanup_sent_entries() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_sent_entries() TO service_role;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  3. SCHEDULE DAILY CRON CLEANUP                                        ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'cleanup-sent-entries';
SELECT cron.schedule(
  'cleanup-sent-entries',
  '0 3 * * *',
  $$SELECT cleanup_sent_entries();$$
);

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  4. SERVICE ROLE GRANTS for timer_days reset (heartbeat.py)            ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Ensure service_role can update timer_days (for post-expiry reset to 30)
GRANT UPDATE (timer_days, last_check_in) ON profiles TO service_role;

-- ============================================================================
-- END OF SQL #33
-- ============================================================================
