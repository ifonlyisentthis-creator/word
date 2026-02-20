-- ============================================================================
-- AFTERWORD — COMPREHENSIVE SQL UPDATE
-- Run this in Supabase SQL Editor.
--
-- This script:
--   1. Adds new columns for themes & soul fire preferences
--   2. Creates update_preferences RPC
--   3. Drops ALL existing RLS policies
--   4. Recreates complete RLS from scratch (A-Z)
--   5. Fixes update_check_in (p_timer_days param rename)
--   6. Fixes update_timer_days (resets last_check_in)
--   7. Drops broken cleanup_sent_entries SQL function
--   8. Complete column-level grants
--   9. Complete trigger guards
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 1 — NEW COLUMNS (themes & soul fire preferences)             ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS selected_theme text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS selected_soul_fire text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS key_backup_encrypted text;

-- Server-managed lifecycle columns used by heartbeat + grace-period flow
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS protocol_executed_at timestamptz;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS last_entry_at timestamptz;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS had_vault_activity boolean DEFAULT false;

-- Valid theme values
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'profiles_theme_check' AND conrelid = 'profiles'::regclass
  ) THEN
    ALTER TABLE profiles ADD CONSTRAINT profiles_theme_check
      CHECK (selected_theme IS NULL OR selected_theme IN (
        'oledVoid','midnightFrost','shadowRose',
        'obsidianSteel','midnightEmber','deepOcean','auroraNight','cosmicDusk'
      ));
  END IF;
END $$;

-- Valid soul fire values
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'profiles_soul_fire_check' AND conrelid = 'profiles'::regclass
  ) THEN
    ALTER TABLE profiles ADD CONSTRAINT profiles_soul_fire_check
      CHECK (selected_soul_fire IS NULL OR selected_soul_fire IN (
        'etherealOrb','goldenPulse','nebulaHeart',
        'voidPortal','plasmaBurst','plasmaCell','toxicCore','crystalAscend'
      ));
  END IF;
END $$;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 2 — NEW RPC: update_preferences                             ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.update_preferences(
  target_user_id uuid,
  p_theme text DEFAULT NULL,
  p_soul_fire text DEFAULT NULL
)
RETURNS profiles
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result profiles;
  sub text;
  -- Theme tier mapping
  theme_tier text;
  sf_tier text;
BEGIN
  IF auth.uid() <> target_user_id THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT subscription_status INTO sub
  FROM profiles WHERE id = target_user_id;

  IF sub IS NULL THEN
    RAISE EXCEPTION 'profile not found';
  END IF;

  -- Validate theme against subscription tier
  IF p_theme IS NOT NULL THEN
    theme_tier := CASE p_theme
      WHEN 'oledVoid' THEN 'free'
      WHEN 'midnightFrost' THEN 'free'
      WHEN 'shadowRose' THEN 'free'
      WHEN 'obsidianSteel' THEN 'pro'
      WHEN 'midnightEmber' THEN 'pro'
      WHEN 'deepOcean' THEN 'pro'
      WHEN 'auroraNight' THEN 'lifetime'
      WHEN 'cosmicDusk' THEN 'lifetime'
      ELSE NULL
    END;
    IF theme_tier IS NULL THEN
      RAISE EXCEPTION 'invalid theme';
    END IF;
    IF theme_tier = 'pro' AND sub NOT IN ('pro','lifetime') THEN
      RAISE EXCEPTION 'theme requires pro or lifetime';
    END IF;
    IF theme_tier = 'lifetime' AND sub <> 'lifetime' THEN
      RAISE EXCEPTION 'theme requires lifetime';
    END IF;
  END IF;

  -- Validate soul fire against subscription tier
  IF p_soul_fire IS NOT NULL THEN
    sf_tier := CASE p_soul_fire
      WHEN 'etherealOrb' THEN 'free'
      WHEN 'goldenPulse' THEN 'free'
      WHEN 'nebulaHeart' THEN 'free'
      WHEN 'voidPortal' THEN 'pro'
      WHEN 'plasmaBurst' THEN 'pro'
      WHEN 'plasmaCell' THEN 'pro'
      WHEN 'toxicCore' THEN 'lifetime'
      WHEN 'crystalAscend' THEN 'lifetime'
      ELSE NULL
    END;
    IF sf_tier IS NULL THEN
      RAISE EXCEPTION 'invalid soul fire style';
    END IF;
    IF sf_tier = 'pro' AND sub NOT IN ('pro','lifetime') THEN
      RAISE EXCEPTION 'soul fire style requires pro or lifetime';
    END IF;
    IF sf_tier = 'lifetime' AND sub <> 'lifetime' THEN
      RAISE EXCEPTION 'soul fire style requires lifetime';
    END IF;
  END IF;

  UPDATE profiles
  SET selected_theme = COALESCE(p_theme, selected_theme),
      selected_soul_fire = COALESCE(p_soul_fire, selected_soul_fire)
  WHERE id = target_user_id
  RETURNING * INTO result;

  RETURN result;
END;
$$;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 3 — FIX update_check_in (param name collision fix)           ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

DROP FUNCTION IF EXISTS public.update_check_in(uuid, integer);

CREATE OR REPLACE FUNCTION public.update_check_in(user_id uuid, p_timer_days int DEFAULT NULL)
RETURNS profiles
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result profiles;
  sub text;
  effective_timer int;
  max_timer int;
BEGIN
  IF auth.uid() <> user_id THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT subscription_status, timer_days
  INTO sub, effective_timer
  FROM profiles
  WHERE id = user_id;

  IF sub IS NULL THEN
    RAISE EXCEPTION 'profile not found';
  END IF;

  IF sub = 'lifetime' THEN
    max_timer := 3650;
  ELSIF sub = 'pro' THEN
    max_timer := 365;
  ELSE
    max_timer := 30;
  END IF;

  IF sub NOT IN ('pro','lifetime') THEN
    effective_timer := 30;
  ELSIF p_timer_days IS NOT NULL THEN
    effective_timer := greatest(7, least(max_timer, p_timer_days));
  END IF;

  UPDATE profiles
  SET last_check_in = now(),
      timer_days = effective_timer,
      warning_sent_at = NULL,
      push_66_sent_at = NULL,
      push_33_sent_at = NULL,
      status = 'active'
  WHERE id = user_id
  RETURNING * INTO result;

  RETURN result;
END;
$$;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 4 — FIX update_timer_days (now resets last_check_in)         ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.update_timer_days(p_timer_days int)
RETURNS profiles
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result profiles;
  sub text;
  max_timer int;
  effective_timer int;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT subscription_status INTO sub
  FROM profiles WHERE id = auth.uid();

  IF sub IS NULL THEN
    RAISE EXCEPTION 'profile not found';
  END IF;

  IF sub = 'lifetime' THEN
    max_timer := 3650;
  ELSIF sub = 'pro' THEN
    max_timer := 365;
  ELSE
    max_timer := 30;
  END IF;

  IF sub NOT IN ('pro','lifetime') THEN
    effective_timer := 30;
  ELSE
    effective_timer := greatest(7, least(max_timer, p_timer_days));
  END IF;

  UPDATE profiles
  SET timer_days = effective_timer,
      last_check_in = now(),
      warning_sent_at = NULL,
      push_66_sent_at = NULL,
      push_33_sent_at = NULL
  WHERE id = auth.uid()
  RETURNING * INTO result;

  RETURN result;
END;
$$;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 5 — OTHER RPC FUNCTIONS                                      ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- 5a. update_sender_name
DROP FUNCTION IF EXISTS public.update_sender_name(text);
CREATE OR REPLACE FUNCTION public.update_sender_name(new_sender_name text)
RETURNS profiles LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE result profiles;
BEGIN
  UPDATE profiles
  SET sender_name = COALESCE(NULLIF(TRIM(new_sender_name), ''), 'Afterword')
  WHERE id = auth.uid()
  RETURNING * INTO result;
  RETURN result;
END;
$$;

-- 5a.1 delete_my_account (authenticated self-delete; hard delete auth user)
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

-- 5b. set_subscription_status (SERVICE ROLE ONLY)
CREATE OR REPLACE FUNCTION public.set_subscription_status(user_id uuid, subscription_status text)
RETURNS profiles LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE result profiles;
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  UPDATE profiles
  SET subscription_status = lower(subscription_status)
  WHERE id = user_id
  RETURNING * INTO result;
  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.set_subscription_status(uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_subscription_status(uuid, text) TO service_role;

-- 5c. edge_set_subscription_status (Edge Function only)
CREATE OR REPLACE FUNCTION public.edge_set_subscription_status(
  target_user_id uuid, new_status text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE old_role text;
BEGIN
  IF new_status NOT IN ('free', 'pro', 'lifetime') THEN
    RAISE EXCEPTION 'invalid subscription status: %', new_status;
  END IF;
  old_role := COALESCE(current_setting('request.jwt.claim.role', true), '');
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  UPDATE profiles SET subscription_status = new_status WHERE id = target_user_id;
  PERFORM set_config('request.jwt.claim.role', old_role, true);
END;
$$;

REVOKE ALL ON FUNCTION public.edge_set_subscription_status(uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.edge_set_subscription_status(uuid, text) TO service_role;

-- 5d. viewer_entry_status (anonymous access for web viewer)
DROP FUNCTION IF EXISTS public.viewer_entry_status(uuid);
CREATE OR REPLACE FUNCTION public.viewer_entry_status(entry_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE rec record;
BEGIN
  SELECT ve.status, p.sender_name
  INTO rec
  FROM vault_entries ve
  JOIN profiles p ON p.id = ve.user_id
  WHERE ve.id = entry_id;

  IF NOT FOUND THEN
    RETURN json_build_object('state', 'expired', 'sender_name', null::text);
  END IF;
  IF rec.status = 'sent' THEN
    RETURN json_build_object('state', 'available', 'sender_name', rec.sender_name);
  END IF;
  RETURN json_build_object('state', 'unavailable');
END;
$$;

REVOKE ALL ON FUNCTION public.viewer_entry_status(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.viewer_entry_status(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.viewer_entry_status(uuid) TO authenticated;

-- 5d2. viewer_get_entry (anonymous access to one specific sent entry)
DROP FUNCTION IF EXISTS public.viewer_get_entry(uuid);
CREATE OR REPLACE FUNCTION public.viewer_get_entry(entry_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE rec record;
BEGIN
  SELECT
    ve.id,
    ve.title,
    ve.data_type,
    ve.payload_encrypted,
    ve.audio_file_path,
    ve.audio_duration_seconds,
    ve.status
  INTO rec
  FROM vault_entries ve
  WHERE ve.id = entry_id
    AND ve.status = 'sent';

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN json_build_object(
    'id', rec.id,
    'title', rec.title,
    'data_type', rec.data_type,
    'payload_encrypted', rec.payload_encrypted,
    'audio_file_path', rec.audio_file_path,
    'audio_duration_seconds', rec.audio_duration_seconds,
    'status', rec.status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.viewer_get_entry(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.viewer_get_entry(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.viewer_get_entry(uuid) TO authenticated;

-- 5e. handle_new_user (auto-create profile on signup)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, sender_name)
  VALUES (
    new.id,
    new.email,
    COALESCE(NULLIF(TRIM(COALESCE(new.raw_user_meta_data->>'name','')), ''), 'Afterword')
  )
  ON CONFLICT (id) DO UPDATE SET email = excluded.email;
  RETURN new;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'on_auth_user_created'
  ) THEN
    EXECUTE 'CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user()';
  END IF;
END $$;

-- 5f. Drop broken cleanup_sent_entries (now handled in Python heartbeat.py)
DROP FUNCTION IF EXISTS public.cleanup_sent_entries();
-- Also drop the old vulnerable function
DROP FUNCTION IF EXISTS public.sync_my_subscription_status(text);
DROP FUNCTION IF EXISTS public.block_subscription_status_changes() CASCADE;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 6 — GUARD TRIGGERS                                           ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- 6a. guard_subscription_status — prevent client from changing sub status
CREATE OR REPLACE FUNCTION public.guard_subscription_status()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF new.subscription_status IS DISTINCT FROM old.subscription_status
     AND COALESCE(current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'subscription_status can only be changed by service role';
  END IF;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS protect_subscription_status ON profiles;
CREATE TRIGGER protect_subscription_status
BEFORE UPDATE ON profiles
FOR EACH ROW EXECUTE FUNCTION public.guard_subscription_status();

-- 6b. guard_timer_days — clamp to subscription tier limits
CREATE OR REPLACE FUNCTION public.guard_timer_days()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE max_timer int;
BEGIN
  IF new.timer_days IS DISTINCT FROM old.timer_days THEN
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
      IF old.subscription_status = 'lifetime' THEN
        max_timer := 3650;
        new.timer_days := greatest(7, least(max_timer, new.timer_days));
      ELSIF old.subscription_status = 'pro' THEN
        max_timer := 365;
        new.timer_days := greatest(7, least(max_timer, new.timer_days));
      ELSE
        new.timer_days := 30;
      END IF;
    END IF;
  END IF;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS profiles_guard_timer_days ON profiles;
CREATE TRIGGER profiles_guard_timer_days
BEFORE UPDATE ON profiles
FOR EACH ROW EXECUTE FUNCTION public.guard_timer_days();

-- 6c. Rate limit vault entry creation (max 1 every 5 seconds)
CREATE OR REPLACE FUNCTION public.enforce_entry_rate_limit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE last_ts timestamptz;
BEGIN
  IF new.user_id <> auth.uid() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  SELECT last_entry_at INTO last_ts FROM profiles WHERE id = new.user_id FOR UPDATE;
  IF last_ts IS NOT NULL AND clock_timestamp() - last_ts < interval '5 seconds' THEN
    RAISE EXCEPTION 'rate limit';
  END IF;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS vault_entries_rate_limit ON vault_entries;
CREATE TRIGGER vault_entries_rate_limit
BEFORE INSERT ON vault_entries
FOR EACH ROW EXECUTE FUNCTION public.enforce_entry_rate_limit();

-- 6d. Bump last_entry_at after insert
CREATE OR REPLACE FUNCTION public.bump_last_entry_at()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE profiles SET last_entry_at = clock_timestamp() WHERE id = new.user_id;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS vault_entries_bump_last_entry ON vault_entries;
CREATE TRIGGER vault_entries_bump_last_entry
AFTER INSERT ON vault_entries
FOR EACH ROW EXECUTE FUNCTION public.bump_last_entry_at();

-- 6e. Enforce audio time bank (600s = 10 min, lifetime only)
CREATE OR REPLACE FUNCTION public.enforce_audio_time_bank()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  total_seconds int;
  sub text;
  new_duration int;
BEGIN
  IF new.data_type <> 'audio' THEN RETURN new; END IF;
  SELECT subscription_status INTO sub FROM profiles WHERE id = new.user_id;
  IF sub <> 'lifetime' THEN RAISE EXCEPTION 'audio vault is lifetime only'; END IF;
  new_duration := COALESCE(new.audio_duration_seconds, 0);
  IF new_duration <= 0 THEN RAISE EXCEPTION 'audio duration required'; END IF;
  SELECT COALESCE(sum(audio_duration_seconds), 0) INTO total_seconds
  FROM vault_entries
  WHERE user_id = new.user_id AND data_type = 'audio' AND status = 'active' AND id <> new.id;
  IF total_seconds + new_duration > 600 THEN
    RAISE EXCEPTION 'audio time bank limit reached';
  END IF;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS vault_entries_audio_bank ON vault_entries;
CREATE TRIGGER vault_entries_audio_bank
BEFORE INSERT OR UPDATE ON vault_entries
FOR EACH ROW EXECUTE FUNCTION public.enforce_audio_time_bank();

-- 6f. Auto-set updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  new.updated_at = now();
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS profiles_set_updated_at ON profiles;
CREATE TRIGGER profiles_set_updated_at
BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS vault_entries_set_updated_at ON vault_entries;
CREATE TRIGGER vault_entries_set_updated_at
BEFORE UPDATE ON vault_entries FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_push_devices_updated_at ON push_devices;
CREATE TRIGGER set_push_devices_updated_at
BEFORE UPDATE ON push_devices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 6g. Guard theme/soul fire on subscription downgrade
CREATE OR REPLACE FUNCTION public.guard_preferences_on_downgrade()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF new.subscription_status IS DISTINCT FROM old.subscription_status THEN
    -- Reset theme to free if no longer qualified
    IF new.selected_theme IN ('obsidianSteel','midnightEmber','deepOcean')
       AND new.subscription_status NOT IN ('pro','lifetime') THEN
      new.selected_theme := NULL;
    END IF;
    IF new.selected_theme IN ('auroraNight','cosmicDusk')
       AND new.subscription_status <> 'lifetime' THEN
      new.selected_theme := NULL;
    END IF;
    -- Reset soul fire to free if no longer qualified
    IF new.selected_soul_fire IN ('voidPortal','plasmaBurst','plasmaCell')
       AND new.subscription_status NOT IN ('pro','lifetime') THEN
      new.selected_soul_fire := NULL;
    END IF;
    IF new.selected_soul_fire IN ('toxicCore','crystalAscend')
       AND new.subscription_status <> 'lifetime' THEN
      new.selected_soul_fire := NULL;
    END IF;
  END IF;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS profiles_guard_preferences ON profiles;
CREATE TRIGGER profiles_guard_preferences
BEFORE UPDATE ON profiles
FOR EACH ROW EXECUTE FUNCTION public.guard_preferences_on_downgrade();

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 7 — DROP ALL EXISTING RLS POLICIES                           ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- profiles
DROP POLICY IF EXISTS profiles_select_own ON profiles;
DROP POLICY IF EXISTS profiles_insert_own ON profiles;
DROP POLICY IF EXISTS profiles_update_own ON profiles;
DROP POLICY IF EXISTS profiles_delete_own ON profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "Users can delete own profile" ON profiles;

-- vault_entries
DROP POLICY IF EXISTS entries_select_own ON vault_entries;
DROP POLICY IF EXISTS entries_select_sent_anon ON vault_entries;
DROP POLICY IF EXISTS entries_insert_own ON vault_entries;
DROP POLICY IF EXISTS entries_update_own ON vault_entries;
DROP POLICY IF EXISTS entries_delete_own ON vault_entries;
DROP POLICY IF EXISTS vault_entries_update ON vault_entries;
DROP POLICY IF EXISTS "Users can view own entries" ON vault_entries;
DROP POLICY IF EXISTS "Users can insert own entries" ON vault_entries;
DROP POLICY IF EXISTS "Users can update own entries" ON vault_entries;
DROP POLICY IF EXISTS "Users can delete own entries" ON vault_entries;

-- push_devices
DROP POLICY IF EXISTS push_devices_select_own ON push_devices;
DROP POLICY IF EXISTS push_devices_insert_own ON push_devices;
DROP POLICY IF EXISTS push_devices_update_own ON push_devices;
DROP POLICY IF EXISTS push_devices_delete_own ON push_devices;

-- vault_entry_tombstones
DROP POLICY IF EXISTS tombstones_select_own ON vault_entry_tombstones;

-- storage
DROP POLICY IF EXISTS vault_audio_read_owner ON storage.objects;
DROP POLICY IF EXISTS vault_audio_read_sent_anon ON storage.objects;
DROP POLICY IF EXISTS vault_audio_insert_lifetime ON storage.objects;
DROP POLICY IF EXISTS vault_audio_update_lifetime ON storage.objects;
DROP POLICY IF EXISTS vault_audio_delete_lifetime ON storage.objects;
DROP POLICY IF EXISTS vault_audio_insert ON storage.objects;
DROP POLICY IF EXISTS vault_audio_select ON storage.objects;
DROP POLICY IF EXISTS vault_audio_update ON storage.objects;
DROP POLICY IF EXISTS vault_audio_delete ON storage.objects;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 8 — ENABLE RLS ON ALL TABLES                                 ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault_entry_tombstones ENABLE ROW LEVEL SECURITY;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 9 — COMPLETE RLS POLICIES (A-Z)                              ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- ── 9a. PROFILES ──

CREATE POLICY profiles_select_own ON profiles
FOR SELECT USING (auth.uid() = id);

CREATE POLICY profiles_insert_own ON profiles
FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY profiles_update_own ON profiles
FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

CREATE POLICY profiles_delete_own ON profiles
FOR DELETE USING (auth.uid() = id);

-- ── 9b. VAULT ENTRIES ──

-- Users can read all their own entries (any status)
CREATE POLICY entries_select_own ON vault_entries
FOR SELECT USING (auth.uid() = user_id);

-- Insert: enforces free tier limit (3 text), subscription gates (destroy=pro, audio=lifetime)
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
  -- Audio requires Lifetime
  AND (
    data_type <> 'audio'
    OR EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.subscription_status = 'lifetime'
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

-- Update: only active entries can be edited, with subscription gates
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
  AND (
    data_type <> 'audio'
    OR EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.subscription_status = 'lifetime'
    )
  )
);

-- Delete: users can delete their own entries (active + sent during grace period)
CREATE POLICY entries_delete_own ON vault_entries
FOR DELETE USING (auth.uid() = user_id AND status <> 'sending');

-- ── 9c. PUSH DEVICES ──

CREATE POLICY push_devices_select_own ON push_devices
FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY push_devices_insert_own ON push_devices
FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE POLICY push_devices_update_own ON push_devices
FOR UPDATE TO authenticated
USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY push_devices_delete_own ON push_devices
FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ── 9d. VAULT ENTRY TOMBSTONES ──

CREATE POLICY tombstones_select_own ON vault_entry_tombstones
FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- ── 9e. STORAGE (vault-audio bucket) ──

INSERT INTO storage.buckets (id, name, public)
VALUES ('vault-audio', 'vault-audio', false)
ON CONFLICT (id) DO NOTHING;

-- Owner can read their own audio files
CREATE POLICY vault_audio_read_owner ON storage.objects
FOR SELECT TO authenticated
USING (bucket_id = 'vault-audio' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Helper: SECURITY DEFINER so the storage policy can check vault_entries
-- even after we revoke direct anon SELECT on the table.
DROP FUNCTION IF EXISTS public.is_sent_audio_path(text);
CREATE OR REPLACE FUNCTION public.is_sent_audio_path(file_path text)
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

-- Anonymous (web viewer) can read audio for sent entries
CREATE POLICY vault_audio_read_sent_anon ON storage.objects
FOR SELECT TO anon
USING (
  bucket_id = 'vault-audio'
  AND public.is_sent_audio_path(name)
);

-- Only Lifetime users can upload audio (folder must match their user_id)
CREATE POLICY vault_audio_insert_lifetime ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'vault-audio'
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid() AND p.subscription_status = 'lifetime'
  )
);

-- Only Lifetime users can update audio
CREATE POLICY vault_audio_update_lifetime ON storage.objects
FOR UPDATE TO authenticated
USING (bucket_id = 'vault-audio' AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (
  bucket_id = 'vault-audio'
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid() AND p.subscription_status = 'lifetime'
  )
);

-- Any authenticated user can delete their own audio (cleanup, downgrade, account deletion)
CREATE POLICY vault_audio_delete_own ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'vault-audio'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 10 — COLUMN-LEVEL GRANTS (lockdown sensitive columns)        ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Revoke broad UPDATE from client roles
REVOKE UPDATE ON profiles FROM authenticated, anon;

-- Authenticated users can only directly UPDATE client-managed encrypted key fields
-- (all other profile mutations go through SECURITY DEFINER RPCs)
GRANT UPDATE (hmac_key_encrypted, key_backup_encrypted) ON profiles TO authenticated;

-- Service role can update server-managed columns (heartbeat + subscription sync)
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

-- Table-level grants
GRANT SELECT, INSERT, DELETE ON TABLE profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE vault_entries TO authenticated;
GRANT SELECT ON TABLE vault_entry_tombstones TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 11 — PERFORMANCE INDEXES                                     ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE INDEX IF NOT EXISTS idx_vault_entries_user_status ON vault_entries (user_id, status);
CREATE INDEX IF NOT EXISTS idx_vault_entries_sent_at ON vault_entries (sent_at) WHERE status = 'sent';
CREATE INDEX IF NOT EXISTS idx_vault_entries_user_created ON vault_entries (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_profiles_active_checkin ON profiles (last_check_in) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_push_devices_user ON push_devices (user_id);
CREATE INDEX IF NOT EXISTS idx_tombstones_user ON vault_entry_tombstones (user_id);
CREATE INDEX IF NOT EXISTS idx_profiles_subscription ON profiles (subscription_status) WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS idx_push_devices_user_token ON push_devices (user_id, fcm_token);

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  SECTION 12 — UNSCHEDULE OLD CRON JOBS                                ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- cleanup_sent_entries is now handled by Python heartbeat.py
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'cleanup-sent-entries';

-- ============================================================================
-- END OF COMPREHENSIVE UPDATE SQL
-- ============================================================================
