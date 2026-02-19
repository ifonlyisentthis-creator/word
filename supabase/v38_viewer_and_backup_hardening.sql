-- ============================================================================
-- AFTERWORD v38 — Production Hardening (Viewer Isolation + Storage Fix)
-- Run this ENTIRE block in Supabase SQL Editor.
--
-- Changes:
--   1) Ensure profiles.key_backup_encrypted column exists + column grants.
--   2) Remove broad anonymous SELECT on vault_entries.
--   3) Add viewer_entry_status SECURITY DEFINER RPC (expired / available).
--   4) Add viewer_get_entry SECURITY DEFINER RPC (fetch single sent entry).
--   5) Add is_sent_audio_path SECURITY DEFINER helper for storage policy.
--   6) Recreate vault_audio_read_sent_anon policy using the helper
--      (old policy used a direct subquery that breaks without anon SELECT).
-- ============================================================================

BEGIN;

-- ── 1. Recovery backup column + column-level grants ────────────────────────

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS key_backup_encrypted text;

REVOKE UPDATE ON profiles FROM authenticated, anon;
GRANT UPDATE (hmac_key_encrypted, key_backup_encrypted) ON profiles TO authenticated;

GRANT UPDATE (
  subscription_status,
  status,
  warning_sent_at,
  push_66_sent_at,
  push_33_sent_at,
  timer_days,
  last_check_in,
  selected_theme,
  selected_soul_fire,
  protocol_executed_at,
  last_entry_at,
  had_vault_activity
) ON profiles TO service_role;

-- ── 2. Remove broad anon table reads on vault_entries ──────────────────────

DROP POLICY IF EXISTS entries_select_sent_anon ON vault_entries;
REVOKE SELECT ON TABLE vault_entries FROM anon;

-- ── 3. viewer_entry_status RPC (check if entry is available/expired) ───────

DROP FUNCTION IF EXISTS public.viewer_entry_status(uuid);
CREATE FUNCTION public.viewer_entry_status(entry_id uuid)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    CASE
      WHEN ve.id IS NULL THEN
        json_build_object('state', 'unavailable', 'sender_name', NULL)
      WHEN t.vault_entry_id IS NOT NULL THEN
        json_build_object('state', 'expired', 'sender_name', t.sender_name)
      ELSE
        json_build_object(
          'state', 'available',
          'sender_name', (
            SELECT p.sender_name FROM profiles p WHERE p.id = ve.user_id
          )
        )
    END
  FROM (SELECT entry_id AS lookup_id) AS q
  LEFT JOIN vault_entries ve ON ve.id = q.lookup_id AND ve.status = 'sent'
  LEFT JOIN vault_entry_tombstones t ON t.vault_entry_id = q.lookup_id
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.viewer_entry_status(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.viewer_entry_status(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.viewer_entry_status(uuid) TO authenticated;

-- ── 4. viewer_get_entry RPC (fetch one sent entry by ID) ───────────────────

DROP FUNCTION IF EXISTS public.viewer_get_entry(uuid);
CREATE FUNCTION public.viewer_get_entry(entry_id uuid)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'id', ve.id,
    'title', ve.title,
    'data_type', ve.data_type,
    'payload_encrypted', ve.payload_encrypted,
    'audio_file_path', ve.audio_file_path,
    'audio_duration_seconds', ve.audio_duration_seconds,
    'status', ve.status
  )
  FROM vault_entries AS ve
  WHERE ve.id = entry_id
    AND ve.status = 'sent'
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.viewer_get_entry(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.viewer_get_entry(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.viewer_get_entry(uuid) TO authenticated;

-- ── 5. Storage helper: is_sent_audio_path ──────────────────────────────────
-- The old vault_audio_read_sent_anon policy used EXISTS(SELECT FROM vault_entries)
-- as the anon role. After revoking anon SELECT on vault_entries, that subquery
-- fails with permission denied. This SECURITY DEFINER function bypasses RLS
-- so the storage policy can still verify the audio belongs to a sent entry.

DROP FUNCTION IF EXISTS public.is_sent_audio_path(text);
CREATE FUNCTION public.is_sent_audio_path(file_path text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM vault_entries ve
    WHERE ve.audio_file_path = file_path
      AND ve.status = 'sent'
  );
$$;

REVOKE ALL ON FUNCTION public.is_sent_audio_path(text) FROM public;
GRANT EXECUTE ON FUNCTION public.is_sent_audio_path(text) TO anon;

-- ── 6. Recreate storage policy using the helper ────────────────────────────

DROP POLICY IF EXISTS vault_audio_read_sent_anon ON storage.objects;
CREATE POLICY vault_audio_read_sent_anon ON storage.objects
FOR SELECT TO anon
USING (
  bucket_id = 'vault-audio'
  AND public.is_sent_audio_path(name)
);

COMMIT;

-- ============================================================================
-- END OF v38 SQL
-- ============================================================================
