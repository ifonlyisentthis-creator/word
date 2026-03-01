-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  v39 — Add 2 new themes + 2 new soul fires (10/10 total)              ║
-- ║                                                                        ║
-- ║  New themes:                                                           ║
-- ║    velvetAbyss    (Pro)      — pitch black + deep burgundy velvet      ║
-- ║    obsidianPrism  (Lifetime) — jet black + prismatic iridescent        ║
-- ║                                                                        ║
-- ║  New soul fires:                                                       ║
-- ║    infinityWell   (Pro)      — recursive dimensional rift              ║
-- ║    phantomPulse   (Lifetime) — ghostly specter with afterimages        ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. UPDATE CHECK CONSTRAINTS — drop old, add new with all 10 values
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_theme_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_theme_check
  CHECK (selected_theme IS NULL OR selected_theme IN (
    'oledVoid','midnightFrost','shadowRose',
    'obsidianSteel','midnightEmber','deepOcean','velvetAbyss',
    'auroraNight','cosmicDusk','obsidianPrism'
  ));

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_soul_fire_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_soul_fire_check
  CHECK (selected_soul_fire IS NULL OR selected_soul_fire IN (
    'etherealOrb','goldenPulse','nebulaHeart',
    'voidPortal','plasmaBurst','plasmaCell','infinityWell',
    'toxicCore','crystalAscend','phantomPulse'
  ));

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. UPDATE update_preferences RPC — add new keys to CASE tier mapping
-- ═══════════════════════════════════════════════════════════════════════════

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

REVOKE ALL ON FUNCTION public.update_preferences(uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_preferences(uuid, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. UPDATE DOWNGRADE GUARD TRIGGER — include new themes/soul fires
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.guard_preferences_on_downgrade()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF new.subscription_status IS DISTINCT FROM old.subscription_status THEN
    -- Reset Pro themes to free if downgraded below Pro
    IF new.selected_theme IN ('obsidianSteel','midnightEmber','deepOcean','velvetAbyss')
       AND new.subscription_status NOT IN ('pro','lifetime') THEN
      new.selected_theme := NULL;
    END IF;
    -- Reset Lifetime themes if downgraded below Lifetime
    IF new.selected_theme IN ('auroraNight','cosmicDusk','obsidianPrism')
       AND new.subscription_status <> 'lifetime' THEN
      new.selected_theme := NULL;
    END IF;
    -- Reset Pro soul fires to free if downgraded below Pro
    IF new.selected_soul_fire IN ('voidPortal','plasmaBurst','plasmaCell','infinityWell')
       AND new.subscription_status NOT IN ('pro','lifetime') THEN
      new.selected_soul_fire := NULL;
    END IF;
    -- Reset Lifetime soul fires if downgraded below Lifetime
    IF new.selected_soul_fire IN ('toxicCore','crystalAscend','phantomPulse')
       AND new.subscription_status <> 'lifetime' THEN
      new.selected_soul_fire := NULL;
    END IF;
  END IF;
  RETURN new;
END;
$$;
