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
-- 2. UPDATE DOWNGRADE GUARD TRIGGER — include new themes/soul fires
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
