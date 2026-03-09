-- ============================================================================
-- AFTERWORD v45 — Remove Soul Fire Haptics + Clean update_preferences
-- Run this in Supabase SQL Editor (safe to re-run).
--
-- This migration:
--   1. Rebuilds update_preferences RPC without p_haptics parameter
--   2. Drops the soul_fire_haptics column from profiles
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  1. REBUILD update_preferences RPC (remove haptics param)              ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Drop all overloads so we can recreate cleanly
DROP FUNCTION IF EXISTS public.update_preferences(uuid, text, text, boolean);
DROP FUNCTION IF EXISTS public.update_preferences(uuid, text, text);

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
      WHEN 'velvetAbyss' THEN 'pro'
      WHEN 'auroraNight' THEN 'lifetime'
      WHEN 'cosmicDusk' THEN 'lifetime'
      WHEN 'obsidianPrism' THEN 'lifetime'
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
      WHEN 'infinityWell' THEN 'pro'
      WHEN 'toxicCore' THEN 'lifetime'
      WHEN 'crystalAscend' THEN 'lifetime'
      WHEN 'phantomPulse' THEN 'lifetime'
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

-- Grants: only authenticated users, never anon
REVOKE ALL ON FUNCTION public.update_preferences(uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_preferences(uuid, text, text) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  2. DROP soul_fire_haptics COLUMN                                      ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

ALTER TABLE profiles DROP COLUMN IF EXISTS soul_fire_haptics;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  3. FIX edge_set_subscription_status — raise on 0-row update           ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- The webhook alias fallback tries multiple UUIDs. If UPDATE matches 0 rows
-- (no profile for that UUID), the old version silently succeeds, so the
-- fallback stops at the wrong UUID. The fix: raise an exception when no
-- profile matches, so the webhook can try the next candidate.

CREATE OR REPLACE FUNCTION public.edge_set_subscription_status(
  target_user_id uuid, new_status text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  old_role text;
  rows_affected int;
BEGIN
  IF new_status NOT IN ('free', 'pro', 'lifetime') THEN
    RAISE EXCEPTION 'invalid subscription status: %', new_status;
  END IF;
  old_role := COALESCE(current_setting('request.jwt.claim.role', true), '');
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  UPDATE profiles
    SET subscription_status = new_status,
        downgrade_email_pending = CASE
          WHEN new_status IN ('pro', 'lifetime') THEN false
          ELSE downgrade_email_pending
        END
    WHERE id = target_user_id;
  GET DIAGNOSTICS rows_affected = ROW_COUNT;
  PERFORM set_config('request.jwt.claim.role', old_role, true);
  IF rows_affected = 0 THEN
    RAISE EXCEPTION 'profile not found for user %', target_user_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.edge_set_subscription_status(uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.edge_set_subscription_status(uuid, text) TO service_role;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  4. FIX guard_preferences_on_downgrade — include ALL premium keys      ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- The original trigger was missing velvetAbyss, obsidianPrism (themes) and
-- infinityWell, phantomPulse (soul fires). A downgraded user could keep
-- these premium selections.

CREATE OR REPLACE FUNCTION public.guard_preferences_on_downgrade()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF new.subscription_status IS DISTINCT FROM old.subscription_status THEN
    -- Reset PRO themes if no longer qualified
    IF new.selected_theme IN ('obsidianSteel','midnightEmber','deepOcean','velvetAbyss')
       AND new.subscription_status NOT IN ('pro','lifetime') THEN
      new.selected_theme := NULL;
    END IF;
    -- Reset LIFETIME themes if no longer qualified
    IF new.selected_theme IN ('auroraNight','cosmicDusk','obsidianPrism')
       AND new.subscription_status <> 'lifetime' THEN
      new.selected_theme := NULL;
    END IF;
    -- Reset PRO soul fires if no longer qualified
    IF new.selected_soul_fire IN ('voidPortal','plasmaBurst','plasmaCell','infinityWell')
       AND new.subscription_status NOT IN ('pro','lifetime') THEN
      new.selected_soul_fire := NULL;
    END IF;
    -- Reset LIFETIME soul fires if no longer qualified
    IF new.selected_soul_fire IN ('toxicCore','crystalAscend','phantomPulse')
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

-- ============================================================================
-- END OF v45 SQL
-- ============================================================================
