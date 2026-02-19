-- ============================================================================
-- AFTERWORD v36 — Theme/Soul-Fire Preference Alignment
-- Run this in Supabase SQL Editor (safe to re-run).
--
-- Why:
--   Flutter app exposes additional free presets:
--   - themes: midnightFrost, shadowRose
--   - soul fire: goldenPulse, nebulaHeart
--
-- This migration aligns DB constraints + update_preferences RPC so those
-- valid free presets no longer fail server-side validation.
-- ============================================================================

-- 1) Align profiles theme constraint with app enum keys
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_theme_check;
ALTER TABLE profiles
  ADD CONSTRAINT profiles_theme_check
  CHECK (
    selected_theme IS NULL OR selected_theme IN (
      'oledVoid','midnightFrost','shadowRose',
      'obsidianSteel','midnightEmber','deepOcean','auroraNight','cosmicDusk'
    )
  );

-- 2) Align profiles soul fire constraint with app enum keys
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_soul_fire_check;
ALTER TABLE profiles
  ADD CONSTRAINT profiles_soul_fire_check
  CHECK (
    selected_soul_fire IS NULL OR selected_soul_fire IN (
      'etherealOrb','goldenPulse','nebulaHeart',
      'voidPortal','plasmaBurst','plasmaCell','toxicCore','crystalAscend'
    )
  );

-- 3) Keep update_preferences tier gating aligned with app/server model
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

REVOKE ALL ON FUNCTION public.update_preferences(uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_preferences(uuid, text, text) TO authenticated;

-- ============================================================================
-- END OF v36 SQL
-- ============================================================================
