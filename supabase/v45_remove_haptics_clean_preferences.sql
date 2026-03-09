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

-- ============================================================================
-- END OF v45 SQL
-- ============================================================================
