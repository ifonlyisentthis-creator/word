-- ============================================================================
-- AFTERWORD v39 — Scale indexes, account deletion fix, storage policy fix
-- Run this in Supabase SQL Editor.
--
-- What this does:
--   1. Fixes delete_my_account() — removes direct storage.objects DELETE
--      (Supabase blocks it with error 42501). Audio cleanup is now done
--      client-side via Storage API before calling this RPC.
--   2. Fixes storage delete policy — allows ANY authenticated user to delete
--      their own audio (not just Lifetime). Prevents orphaned files on
--      downgrade or account deletion.
--   3. Adds missing performance indexes for million-user scale.
--
-- Safe to re-run (all statements are idempotent).
-- ============================================================================

-- ── 1. Fix delete_my_account (remove storage.objects direct delete) ──

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  uid uuid;
BEGIN
  uid := auth.uid();
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- Audio storage cleanup is done client-side via Storage API before calling
  -- this RPC (direct SQL DELETE on storage.objects is blocked by Supabase).

  -- Delete auth identity; cascades to profiles/vault_entries/push_devices/tombstones.
  DELETE FROM auth.users WHERE id = uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_account() FROM public;
REVOKE ALL ON FUNCTION public.delete_my_account() FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

-- ── 2. Fix storage delete policy (allow any user to delete own audio) ──

DROP POLICY IF EXISTS vault_audio_delete_lifetime ON storage.objects;
DROP POLICY IF EXISTS vault_audio_delete_own ON storage.objects;

CREATE POLICY vault_audio_delete_own ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'vault-audio'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- ── 3. Missing performance indexes ──

CREATE INDEX IF NOT EXISTS idx_tombstones_user
  ON vault_entry_tombstones (user_id);

CREATE INDEX IF NOT EXISTS idx_profiles_subscription
  ON profiles (subscription_status) WHERE status = 'active';

CREATE UNIQUE INDEX IF NOT EXISTS idx_push_devices_user_token
  ON push_devices (user_id, fcm_token);

-- ============================================================================
-- END v39
-- ============================================================================
