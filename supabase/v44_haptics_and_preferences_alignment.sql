-- ============================================================================
-- AFTERWORD v44 — Haptics Column + Theme/Soul-Fire Alignment
-- Run this in Supabase SQL Editor (safe to re-run).
--
-- This migration:
--   1. Adds soul_fire_haptics boolean column to profiles
--   2. Aligns theme constraint with all app enum keys (adds velvetAbyss, obsidianPrism)
--   3. Aligns soul fire constraint with all app enum keys (adds infinityWell, phantomPulse)
--   4. Rebuilds update_preferences RPC to handle haptics + new theme/SF keys
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  1. ADD soul_fire_haptics COLUMN                                       ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS soul_fire_haptics boolean DEFAULT false;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  2. ALIGN THEME CONSTRAINT (add velvetAbyss, obsidianPrism)            ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_theme_check;
ALTER TABLE profiles
  ADD CONSTRAINT profiles_theme_check
  CHECK (
    selected_theme IS NULL OR selected_theme IN (
      'oledVoid','midnightFrost','shadowRose',
      'obsidianSteel','midnightEmber','deepOcean','velvetAbyss',
      'auroraNight','cosmicDusk','obsidianPrism'
    )
  );

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  3. ALIGN SOUL FIRE CONSTRAINT (add infinityWell, phantomPulse)        ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_soul_fire_check;
ALTER TABLE profiles
  ADD CONSTRAINT profiles_soul_fire_check
  CHECK (
    selected_soul_fire IS NULL OR selected_soul_fire IN (
      'etherealOrb','goldenPulse','nebulaHeart',
      'voidPortal','plasmaBurst','plasmaCell','infinityWell',
      'toxicCore','crystalAscend','phantomPulse'
    )
  );

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  4. REBUILD update_preferences RPC (haptics + all keys)                ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Drop all overloads so we can recreate cleanly
DROP FUNCTION IF EXISTS public.update_preferences(uuid, text, text);
DROP FUNCTION IF EXISTS public.update_preferences(uuid, text, text, boolean);

CREATE OR REPLACE FUNCTION public.update_preferences(
  target_user_id uuid,
  p_theme text DEFAULT NULL,
  p_soul_fire text DEFAULT NULL,
  p_haptics boolean DEFAULT NULL
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
      selected_soul_fire = COALESCE(p_soul_fire, selected_soul_fire),
      soul_fire_haptics = COALESCE(p_haptics, soul_fire_haptics)
  WHERE id = target_user_id
  RETURNING * INTO result;

  RETURN result;
END;
$$;

-- Grants: only authenticated users, never anon
REVOKE ALL ON FUNCTION public.update_preferences(uuid, text, text, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_preferences(uuid, text, text, boolean) TO authenticated;

-- Grant service_role UPDATE on the new column for heartbeat downgrade handler
GRANT UPDATE (soul_fire_haptics) ON profiles TO service_role;

-- ============================================================================
-- END OF v44 SQL
-- ============================================================================
