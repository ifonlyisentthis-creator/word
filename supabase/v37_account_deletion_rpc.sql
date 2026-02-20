-- ============================================================================
-- AFTERWORD v37 — True Account Deletion RPC
-- Run this in Supabase SQL Editor.
--
-- Why:
--   The client-side delete flow removed profile-linked rows but did not delete
--   auth.users, allowing the same auth identity to sign in again.
--
-- What this adds:
--   - public.delete_my_account() SECURITY DEFINER RPC
--   - Deletes auth.users row (which cascades to profiles/vault_entries/etc.)
--   NOTE: Audio storage cleanup is done client-side via the Storage API
--         before calling this RPC (direct SQL on storage.objects is blocked).
--   - Grants EXECUTE to authenticated only
--
-- Safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, storage
AS $$
DECLARE
  uid uuid;
BEGIN
  uid := auth.uid();
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  DELETE FROM auth.users WHERE id = uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_account() FROM public;
REVOKE ALL ON FUNCTION public.delete_my_account() FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

-- ============================================================================
-- Rollback (manual):
--   REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM authenticated;
--   DROP FUNCTION IF EXISTS public.delete_my_account();
-- ============================================================================
