-- ============================================================================
-- AFTERWORD SQL #58 — Audio Vault for Pro + Webhook Support
-- Run this in Supabase SQL Editor.
--
-- Changes:
--   1. Update enforce_audio_time_bank() — Pro gets 60s, Lifetime gets 600s
--   2. Update RLS insert/update policies — allow audio for Pro users
--   3. Update storage policies — allow Pro users to upload/update audio
--   4. Update guard_preferences_on_downgrade trigger — no change needed
--      (audio cleanup is handled by heartbeat, not by DB trigger)
--
-- Safe to re-run (all statements are idempotent).
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  1. UPDATE enforce_audio_time_bank — Pro (60s) + Lifetime (600s)       ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.enforce_audio_time_bank()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  total_seconds int;
  sub text;
  new_duration int;
  max_bank int;
BEGIN
  IF new.data_type <> 'audio' THEN RETURN new; END IF;

  SELECT subscription_status INTO sub
  FROM profiles WHERE id = new.user_id;

  -- Pro and Lifetime can use audio vault
  IF sub NOT IN ('pro', 'lifetime') THEN
    RAISE EXCEPTION 'audio vault requires pro or lifetime';
  END IF;

  new_duration := COALESCE(new.audio_duration_seconds, 0);
  IF new_duration <= 0 THEN
    RAISE EXCEPTION 'audio duration required';
  END IF;

  -- Tier-based time bank limits
  IF sub = 'lifetime' THEN
    max_bank := 600;   -- 10 minutes
  ELSE
    max_bank := 60;    -- 1 minute (pro)
  END IF;

  SELECT COALESCE(sum(audio_duration_seconds), 0) INTO total_seconds
  FROM vault_entries
  WHERE user_id = new.user_id
    AND data_type = 'audio'
    AND status = 'active'
    AND id <> new.id;

  IF total_seconds + new_duration > max_bank THEN
    RAISE EXCEPTION 'audio time bank limit reached';
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS vault_entries_audio_bank ON vault_entries;
CREATE TRIGGER vault_entries_audio_bank
BEFORE INSERT OR UPDATE ON vault_entries
FOR EACH ROW EXECUTE FUNCTION public.enforce_audio_time_bank();

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  2. UPDATE RLS POLICIES — allow audio for Pro users                    ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- 2a. Insert policy: change audio gate from lifetime-only to pro+lifetime
DROP POLICY IF EXISTS entries_insert_own ON vault_entries;
CREATE POLICY entries_insert_own ON vault_entries
FOR INSERT WITH CHECK (
  auth.uid() = user_id
  AND status = 'active'
  -- Destroy mode requires Pro/Lifetime
  AND (
    action_type <> 'destroy'
    OR EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.subscription_status IN ('pro','lifetime')
    )
  )
  -- Audio requires Pro/Lifetime (was: Lifetime only)
  AND (
    data_type <> 'audio'
    OR EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.subscription_status IN ('pro','lifetime')
    )
  )
  -- Free users: max 3 active text items
  AND (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.subscription_status IN ('pro','lifetime')
    )
    OR (
      SELECT count(*) FROM vault_entries ve
      WHERE ve.user_id = auth.uid()
        AND ve.status = 'active'
        AND ve.data_type = 'text'
    ) < 3
  )
);

-- 2b. Update policy: change audio gate from lifetime-only to pro+lifetime
DROP POLICY IF EXISTS entries_update_own ON vault_entries;
CREATE POLICY entries_update_own ON vault_entries
FOR UPDATE USING (auth.uid() = user_id AND status = 'active')
WITH CHECK (
  auth.uid() = user_id
  AND status = 'active'
  AND (
    action_type <> 'destroy'
    OR EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.subscription_status IN ('pro','lifetime')
    )
  )
  -- Audio requires Pro/Lifetime (was: Lifetime only)
  AND (
    data_type <> 'audio'
    OR EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.subscription_status IN ('pro','lifetime')
    )
  )
);

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  3. UPDATE STORAGE POLICIES — allow Pro users to upload/update audio   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- 3a. Insert: was lifetime-only, now pro+lifetime
DROP POLICY IF EXISTS vault_audio_insert_lifetime ON storage.objects;
DROP POLICY IF EXISTS vault_audio_insert_paid ON storage.objects;
CREATE POLICY vault_audio_insert_paid ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'vault-audio'
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid() AND p.subscription_status IN ('pro','lifetime')
  )
);

-- 3b. Update: was lifetime-only, now pro+lifetime
DROP POLICY IF EXISTS vault_audio_update_lifetime ON storage.objects;
DROP POLICY IF EXISTS vault_audio_update_paid ON storage.objects;
CREATE POLICY vault_audio_update_paid ON storage.objects
FOR UPDATE TO authenticated
USING (bucket_id = 'vault-audio' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (
  bucket_id = 'vault-audio'
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid() AND p.subscription_status IN ('pro','lifetime')
  )
);

-- 3c. Read owner policy stays the same (already allows any authenticated owner)
-- 3d. Delete policy stays the same (already allows any authenticated owner)
-- 3e. Anon read for sent entries stays the same

-- ============================================================================
-- END OF SQL #58
-- ============================================================================
