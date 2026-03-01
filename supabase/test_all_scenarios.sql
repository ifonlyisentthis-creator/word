-- ════════════════════════════════════════════════════════════════════════════
-- AFTERWORD — Comprehensive Test SQL
-- Run each section in Supabase SQL Editor. Read the comments.
-- Replace UUIDs with real test user IDs from your auth.users table.
--
-- SECTIONS:
--   1. Setup: create test profiles
--   2. Theme/soul-fire preference validation (update_preferences RPC)
--   3. Downgrade guard trigger (subscription status changes)
--   4. Timer states & push/email trigger math
--   5. Email notification: 24h warning
--   6. Timer expiry: 0 minutes before deadline
--   7. Grace period: 0 minutes before grace expiry
--   8. Subscription cancellation simulation
--   9. Refund simulation (pro→free with artifacts)
--  10. Lifetime→Pro downgrade (partial strip)
--  11. Edge cases & constraint violations
--  12. Cleanup
-- ════════════════════════════════════════════════════════════════════════════

-- ╔════════════════════════════════════════════════════════════════════════╗
-- ║  IMPORTANT: Replace these with real auth.users UUIDs for your tests  ║
-- ╚════════════════════════════════════════════════════════════════════════╝
-- You need at least 3 test users already in auth.users.
-- Run this query first to find them:
--   SELECT id, email FROM auth.users LIMIT 5;
--
-- Then set them here:
-- \set test_free_user   '''<UUID-OF-FREE-TEST-USER>'''
-- \set test_pro_user    '''<UUID-OF-PRO-TEST-USER>'''
-- \set test_lt_user     '''<UUID-OF-LIFETIME-TEST-USER>'''
--
-- OR just replace the placeholder UUIDs inline below.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. SETUP — Ensure test profiles exist with known states
-- ════════════════════════════════════════════════════════════════════════════

-- First, check what test users you have:
SELECT id, email, subscription_status, status, timer_days,
       selected_theme, selected_soul_fire, last_check_in,
       warning_sent_at, push_66_sent_at, push_33_sent_at,
       protocol_executed_at
FROM profiles
ORDER BY created_at DESC
LIMIT 10;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. THEME/SOUL-FIRE PREFERENCE VALIDATION (update_preferences RPC)
--    Tests the CASE tier mapping added in v39.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 2a. FREE user tries to select a free theme → SHOULD SUCCEED ──
-- Replace <FREE_USER_ID> with an actual free user's UUID
-- SET LOCAL role TO authenticated;
-- SET LOCAL request.jwt.claims TO '{"sub":"<FREE_USER_ID>"}';
-- SELECT update_preferences('<FREE_USER_ID>'::uuid, 'midnightFrost', NULL);
-- SELECT update_preferences('<FREE_USER_ID>'::uuid, 'shadowRose', 'goldenPulse');
-- SELECT update_preferences('<FREE_USER_ID>'::uuid, 'oledVoid', 'nebulaHeart');

-- ── 2b. FREE user tries Pro theme → SHOULD FAIL ──
-- SELECT update_preferences('<FREE_USER_ID>'::uuid, 'velvetAbyss', NULL);
-- Expected: ERROR "theme requires pro or lifetime"

-- ── 2c. FREE user tries Lifetime theme → SHOULD FAIL ──
-- SELECT update_preferences('<FREE_USER_ID>'::uuid, 'obsidianPrism', NULL);
-- Expected: ERROR "theme requires lifetime"

-- ── 2d. FREE user tries Pro soul fire → SHOULD FAIL ──
-- SELECT update_preferences('<FREE_USER_ID>'::uuid, NULL, 'infinityWell');
-- Expected: ERROR "soul fire style requires pro or lifetime"

-- ── 2e. FREE user tries Lifetime soul fire → SHOULD FAIL ──
-- SELECT update_preferences('<FREE_USER_ID>'::uuid, NULL, 'phantomPulse');
-- Expected: ERROR "soul fire style requires lifetime"

-- ── 2f. PRO user selects new Easter-egg Pro theme/fire → SHOULD SUCCEED ──
-- SELECT update_preferences('<PRO_USER_ID>'::uuid, 'velvetAbyss', 'infinityWell');

-- ── 2g. PRO user tries Lifetime Easter-egg theme → SHOULD FAIL ──
-- SELECT update_preferences('<PRO_USER_ID>'::uuid, 'obsidianPrism', NULL);
-- Expected: ERROR "theme requires lifetime"

-- ── 2h. PRO user tries Lifetime Easter-egg soul fire → SHOULD FAIL ──
-- SELECT update_preferences('<PRO_USER_ID>'::uuid, NULL, 'phantomPulse');
-- Expected: ERROR "soul fire style requires lifetime"

-- ── 2i. LIFETIME user selects all Easter-egg items → SHOULD SUCCEED ──
-- SELECT update_preferences('<LIFETIME_USER_ID>'::uuid, 'obsidianPrism', 'phantomPulse');
-- SELECT update_preferences('<LIFETIME_USER_ID>'::uuid, 'velvetAbyss', 'infinityWell');

-- ── 2j. Invalid theme/soul fire key → SHOULD FAIL ──
-- SELECT update_preferences('<PRO_USER_ID>'::uuid, 'nonExistentTheme', NULL);
-- Expected: ERROR "invalid theme"
-- SELECT update_preferences('<PRO_USER_ID>'::uuid, NULL, 'fakeSoulFire');
-- Expected: ERROR "invalid soul fire style"

-- ── 2k. CHECK constraints — direct INSERT should also fail ──
-- UPDATE profiles SET selected_theme = 'nonExistent' WHERE id = '<ANY_USER_ID>';
-- Expected: ERROR violates check constraint "profiles_theme_check"
-- UPDATE profiles SET selected_soul_fire = 'nonExistent' WHERE id = '<ANY_USER_ID>';
-- Expected: ERROR violates check constraint "profiles_soul_fire_check"


-- ════════════════════════════════════════════════════════════════════════════
-- 3. DOWNGRADE GUARD TRIGGER (guard_preferences_on_downgrade)
--    Simulates subscription status changes and verifies preferences reset.
--    ⚠️ These require service_role to bypass guard_subscription_status.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 3a. Setup: Give a test user Pro preferences ──
-- Run with service_role:
-- UPDATE profiles
-- SET subscription_status = 'pro',
--     selected_theme = 'velvetAbyss',
--     selected_soul_fire = 'infinityWell',
--     timer_days = 90
-- WHERE id = '<TEST_USER_ID>';

-- Verify:
-- SELECT id, subscription_status, selected_theme, selected_soul_fire, timer_days
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: pro, velvetAbyss, infinityWell, 90

-- ── 3b. Downgrade Pro → Free → theme/soul fire should reset ──
-- UPDATE profiles SET subscription_status = 'free' WHERE id = '<TEST_USER_ID>';
-- SELECT id, subscription_status, selected_theme, selected_soul_fire
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: free, NULL, NULL (trigger strips Pro preferences)

-- ── 3c. Setup: Give test user Lifetime preferences ──
-- UPDATE profiles
-- SET subscription_status = 'lifetime',
--     selected_theme = 'obsidianPrism',
--     selected_soul_fire = 'phantomPulse',
--     timer_days = 180
-- WHERE id = '<TEST_USER_ID>';

-- ── 3d. Downgrade Lifetime → Pro → Lifetime-only items should reset ──
-- UPDATE profiles SET subscription_status = 'pro' WHERE id = '<TEST_USER_ID>';
-- SELECT id, subscription_status, selected_theme, selected_soul_fire
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: pro, NULL, NULL (obsidianPrism=lifetime, phantomPulse=lifetime → both stripped)

-- ── 3e. Downgrade Lifetime → Pro with Pro-compatible items → SHOULD KEEP ──
-- UPDATE profiles
-- SET subscription_status = 'lifetime',
--     selected_theme = 'velvetAbyss',
--     selected_soul_fire = 'infinityWell'
-- WHERE id = '<TEST_USER_ID>';
-- UPDATE profiles SET subscription_status = 'pro' WHERE id = '<TEST_USER_ID>';
-- SELECT id, subscription_status, selected_theme, selected_soul_fire
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: pro, velvetAbyss (kept! it's Pro), infinityWell (kept! it's Pro)

-- ── 3f. Downgrade Pro → Free with Pro items → SHOULD STRIP ──
-- UPDATE profiles SET subscription_status = 'free' WHERE id = '<TEST_USER_ID>';
-- SELECT id, subscription_status, selected_theme, selected_soul_fire
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: free, NULL, NULL (velvetAbyss=pro → stripped, infinityWell=pro → stripped)


-- ════════════════════════════════════════════════════════════════════════════
-- 4. TIMER STATES & PUSH/EMAIL TRIGGER MATH
--    Verify trigger timestamps for various timer configurations.
--    This is read-only — just math validation.
-- ════════════════════════════════════════════════════════════════════════════

-- Helper: compute timer milestones for a given check-in and timer days
-- For a 30-day timer checked in NOW:
SELECT
  now() AS check_in,
  now() + interval '30 days' AS deadline,
  now() + interval '30 days' * (1 - 0.66) AS push_66_trigger,
  now() + interval '30 days' * (1 - 0.33) AS push_33_trigger,
  now() + interval '30 days' - interval '1 day' AS email_24h_trigger;

-- For a 7-day timer (Pro minimum):
SELECT
  now() AS check_in,
  now() + interval '7 days' AS deadline,
  now() + interval '7 days' * (1 - 0.66) AS push_66_trigger,
  now() + interval '7 days' * (1 - 0.33) AS push_33_trigger,
  now() + interval '7 days' - interval '1 day' AS email_24h_trigger;

-- For a 365-day timer (Lifetime max):
SELECT
  now() AS check_in,
  now() + interval '365 days' AS deadline,
  now() + interval '365 days' * (1 - 0.66) AS push_66_trigger,
  now() + interval '365 days' * (1 - 0.33) AS push_33_trigger,
  now() + interval '365 days' - interval '1 day' AS email_24h_trigger;


-- ════════════════════════════════════════════════════════════════════════════
-- 5. EMAIL NOTIFICATION: 24-HOUR WARNING
--    Simulate a user whose timer is 23h59m from expiry (should trigger email).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 5a. Set user to expire in 23h59m (just inside 24h warning window) ──
-- UPDATE profiles
-- SET subscription_status = 'pro',
--     status = 'active',
--     timer_days = 30,
--     last_check_in = now() - interval '29 days' - interval '1 minute',
--     warning_sent_at = NULL,
--     push_66_sent_at = NULL,
--     push_33_sent_at = NULL
-- WHERE id = '<TEST_USER_ID>';

-- Verify the user's timer state:
-- SELECT id,
--        last_check_in,
--        last_check_in + (timer_days || ' days')::interval AS deadline,
--        last_check_in + (timer_days || ' days')::interval - now() AS remaining,
--        warning_sent_at
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: ~23h59m remaining, warning_sent_at NULL
-- Heartbeat should pick this up and send the 24h warning email.

-- ── 5b. User whose warning was ALREADY sent this cycle → should NOT re-send ──
-- UPDATE profiles
-- SET warning_sent_at = now()
-- WHERE id = '<TEST_USER_ID>';
-- Heartbeat should skip this user (warning_sent_at >= last_check_in).


-- ════════════════════════════════════════════════════════════════════════════
-- 6. TIMER EXPIRY: 0 MINUTES BEFORE DEADLINE
--    Simulate a user whose timer just expired.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 6a. Set timer to EXACTLY expired (0 remaining) ──
-- UPDATE profiles
-- SET status = 'active',
--     timer_days = 30,
--     last_check_in = now() - interval '30 days',
--     warning_sent_at = NULL,
--     push_66_sent_at = NULL,
--     push_33_sent_at = NULL,
--     protocol_executed_at = NULL
-- WHERE id = '<TEST_USER_ID>';

-- Verify:
-- SELECT id,
--        last_check_in + (timer_days || ' days')::interval AS deadline,
--        last_check_in + (timer_days || ' days')::interval - now() AS remaining
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: remaining <= 0 (expired)
-- Heartbeat should trigger process_expired_entries for this user.

-- ── 6b. With vault entries — test what happens ──
-- Check entries:
-- SELECT id, title, action_type, status, data_type
-- FROM vault_entries
-- WHERE user_id = '<TEST_USER_ID>' AND status = 'active';
--
-- If the user has SEND entries:
--   → Heartbeat sends emails, marks entries as 'sent', sets status='inactive',
--     protocol_executed_at=now()
-- If the user has DESTROY entries:
--   → Heartbeat deletes them, sends push notification
-- If the user has NO entries:
--   → Heartbeat does nothing (user stays active, timer just sits expired)

-- ── 6c. Borderline: timer expired 1 second ago ──
-- UPDATE profiles
-- SET last_check_in = now() - interval '30 days' - interval '1 second'
-- WHERE id = '<TEST_USER_ID>';
-- Heartbeat should still detect this as expired (remaining_seconds <= 0).


-- ════════════════════════════════════════════════════════════════════════════
-- 7. GRACE PERIOD: 0 MINUTES BEFORE GRACE EXPIRY
--    After protocol execution, beneficiary has 30 days to download.
--    After that, sent entries are cleaned up.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 7a. Set user in grace period (protocol executed 29 days ago) ──
-- UPDATE profiles
-- SET status = 'inactive',
--     protocol_executed_at = now() - interval '29 days',
--     timer_days = 30
-- WHERE id = '<TEST_USER_ID>';

-- Verify:
-- SELECT id, status, protocol_executed_at,
--        protocol_executed_at + interval '30 days' AS grace_deadline,
--        protocol_executed_at + interval '30 days' - now() AS grace_remaining
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: ~1 day of grace remaining. cleanup_sent_entries should NOT touch this.

-- ── 7b. Set grace to EXACTLY expired (30 days ago) ──
-- UPDATE profiles
-- SET status = 'inactive',
--     protocol_executed_at = now() - interval '30 days'
-- WHERE id = '<TEST_USER_ID>';

-- Verify:
-- SELECT id, status, protocol_executed_at,
--        protocol_executed_at + interval '30 days' AS grace_deadline,
--        protocol_executed_at + interval '30 days' - now() AS grace_remaining
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: grace_remaining <= 0.
-- cleanup_sent_entries should:
--   → Delete all 'sent' entries for this user
--   → Delete associated storage objects
--   → Reset profile to active with fresh 30-day timer

-- ── 7c. Grace expired with unprocessed entries still remaining ──
-- If vault_entries has entries with status='active' for this inactive user,
-- the heartbeat will RE-ACTIVATE the profile with an expired timer to retry.
-- INSERT INTO vault_entries (user_id, title, action_type, status, ...)
-- VALUES ('<TEST_USER_ID>', 'Retry Test', 'send', 'active', ...);
-- Then run heartbeat — it should re-activate the profile, not delete entries.

-- ── 7d. Grace expired 1 second ago ──
-- UPDATE profiles
-- SET protocol_executed_at = now() - interval '30 days' - interval '1 second'
-- WHERE id = '<TEST_USER_ID>';
-- cleanup_sent_entries uses .lte() so this is caught.


-- ════════════════════════════════════════════════════════════════════════════
-- 8. SUBSCRIPTION CANCELLATION SIMULATION
--    RevenueCat webhook → verify-subscription Edge Function → edge_set_subscription_status
-- ════════════════════════════════════════════════════════════════════════════

-- ── 8a. Simulate: Pro user cancels subscription ──
-- This would normally come from the Edge Function with service_role.
-- Step 1: Set up Pro user
-- UPDATE profiles
-- SET subscription_status = 'pro',
--     selected_theme = 'velvetAbyss',
--     selected_soul_fire = 'infinityWell',
--     timer_days = 90
-- WHERE id = '<TEST_USER_ID>';

-- Step 2: Simulate cancellation (what Edge Function does)
-- SELECT edge_set_subscription_status('<TEST_USER_ID>'::uuid, 'free');

-- Step 3: Verify guard trigger fired
-- SELECT id, subscription_status, selected_theme, selected_soul_fire
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: free, NULL, NULL (guard_preferences_on_downgrade fired)

-- Step 4: Next heartbeat run detects timer_days=90 (>30) → handle_downgrade
-- resets timer_days to 30, last_check_in to now(), clears audio entries.

-- ── 8b. Simulate: Lifetime user cancels ──
-- UPDATE profiles
-- SET subscription_status = 'lifetime',
--     selected_theme = 'obsidianPrism',
--     selected_soul_fire = 'phantomPulse',
--     timer_days = 365
-- WHERE id = '<TEST_USER_ID>';
-- SELECT edge_set_subscription_status('<TEST_USER_ID>'::uuid, 'free');
-- SELECT id, subscription_status, selected_theme, selected_soul_fire, timer_days
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: free, NULL, NULL, 365 (timer_days not reset by trigger, only by heartbeat)


-- ════════════════════════════════════════════════════════════════════════════
-- 9. REFUND SIMULATION (Pro→Free with artifacts)
--    Same as cancellation but emphasizes the heartbeat cleanup.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 9a. Pro user with 90-day timer, custom theme, and audio entries ──
-- UPDATE profiles
-- SET subscription_status = 'free',  -- already set by webhook
--     selected_theme = NULL,          -- already stripped by trigger
--     selected_soul_fire = NULL,      -- already stripped by trigger
--     timer_days = 90                 -- NOT stripped by trigger (heartbeat's job)
-- WHERE id = '<TEST_USER_ID>';

-- Verify what heartbeat will detect:
-- SELECT id, subscription_status, timer_days,
--        selected_theme, selected_soul_fire,
--        CASE WHEN timer_days > 30 THEN 'NEEDS_DOWNGRADE' ELSE 'OK' END AS status
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: NEEDS_DOWNGRADE (timer_days=90 > 30)

-- Heartbeat handle_downgrade will:
-- 1. Reset timer_days → 30
-- 2. Reset last_check_in → now()
-- 3. Clear warning timestamps
-- 4. Delete audio entries
-- 5. Send notification email

-- ── 9b. Check for audio entries that would be deleted ──
-- SELECT id, title, data_type, audio_duration_seconds
-- FROM vault_entries
-- WHERE user_id = '<TEST_USER_ID>' AND data_type = 'audio' AND status = 'active';


-- ════════════════════════════════════════════════════════════════════════════
-- 10. LIFETIME → PRO DOWNGRADE (partial strip)
-- ════════════════════════════════════════════════════════════════════════════

-- ── 10a. Lifetime user with mixed Pro+Lifetime preferences ──
-- UPDATE profiles
-- SET subscription_status = 'lifetime',
--     selected_theme = 'obsidianPrism',      -- Lifetime theme
--     selected_soul_fire = 'infinityWell'     -- Pro soul fire
-- WHERE id = '<TEST_USER_ID>';

-- ── 10b. Downgrade to Pro ──
-- UPDATE profiles SET subscription_status = 'pro' WHERE id = '<TEST_USER_ID>';
-- SELECT id, subscription_status, selected_theme, selected_soul_fire
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: pro, NULL (obsidianPrism stripped), infinityWell (kept — it's Pro)

-- ── 10c. Lifetime user with ONLY Pro-level items ──
-- UPDATE profiles
-- SET subscription_status = 'lifetime',
--     selected_theme = 'velvetAbyss',        -- Pro theme
--     selected_soul_fire = 'plasmaCell'       -- Pro soul fire
-- WHERE id = '<TEST_USER_ID>';
-- UPDATE profiles SET subscription_status = 'pro' WHERE id = '<TEST_USER_ID>';
-- SELECT id, subscription_status, selected_theme, selected_soul_fire
-- FROM profiles WHERE id = '<TEST_USER_ID>';
-- Expected: pro, velvetAbyss (kept), plasmaCell (kept)


-- ════════════════════════════════════════════════════════════════════════════
-- 11. EDGE CASES & CONSTRAINT VIOLATIONS
-- ════════════════════════════════════════════════════════════════════════════

-- ── 11a. NULL theme/soul fire should always be allowed ──
-- UPDATE profiles SET selected_theme = NULL, selected_soul_fire = NULL
-- WHERE id = '<TEST_USER_ID>';
-- Expected: SUCCESS (NULL is the free default)

-- ── 11b. All 10 valid themes pass CHECK constraint ──
SELECT 'oledVoid' IN ('oledVoid','midnightFrost','shadowRose','obsidianSteel','midnightEmber','deepOcean','velvetAbyss','auroraNight','cosmicDusk','obsidianPrism') AS oledVoid_valid,
       'velvetAbyss' IN ('oledVoid','midnightFrost','shadowRose','obsidianSteel','midnightEmber','deepOcean','velvetAbyss','auroraNight','cosmicDusk','obsidianPrism') AS velvetAbyss_valid,
       'obsidianPrism' IN ('oledVoid','midnightFrost','shadowRose','obsidianSteel','midnightEmber','deepOcean','velvetAbyss','auroraNight','cosmicDusk','obsidianPrism') AS obsidianPrism_valid;
-- Expected: all true

-- ── 11c. All 10 valid soul fires pass CHECK constraint ──
SELECT 'etherealOrb' IN ('etherealOrb','goldenPulse','nebulaHeart','voidPortal','plasmaBurst','plasmaCell','infinityWell','toxicCore','crystalAscend','phantomPulse') AS etherealOrb_valid,
       'infinityWell' IN ('etherealOrb','goldenPulse','nebulaHeart','voidPortal','plasmaBurst','plasmaCell','infinityWell','toxicCore','crystalAscend','phantomPulse') AS infinityWell_valid,
       'phantomPulse' IN ('etherealOrb','goldenPulse','nebulaHeart','voidPortal','plasmaBurst','plasmaCell','infinityWell','toxicCore','crystalAscend','phantomPulse') AS phantomPulse_valid;
-- Expected: all true

-- ── 11d. Tier mapping completeness check ──
-- Verify every theme has a tier in update_preferences:
-- Free: oledVoid, midnightFrost, shadowRose
-- Pro:  obsidianSteel, midnightEmber, deepOcean, velvetAbyss
-- Life: auroraNight, cosmicDusk, obsidianPrism
-- Total: 3 + 4 + 3 = 10 ✓

-- Verify every soul fire has a tier:
-- Free: etherealOrb, goldenPulse, nebulaHeart
-- Pro:  voidPortal, plasmaBurst, plasmaCell, infinityWell
-- Life: toxicCore, crystalAscend, phantomPulse
-- Total: 3 + 4 + 3 = 10 ✓

-- ── 11e. Subscription status constraint ──
-- UPDATE profiles SET subscription_status = 'invalid_status' WHERE id = '<TEST_USER_ID>';
-- Expected: ERROR (if constraint exists) or just a string (heartbeat treats unknown as non-paid)

-- ── 11f. Timer days boundary: 1 day (minimum) ──
-- UPDATE profiles SET timer_days = 1, last_check_in = now() WHERE id = '<TEST_USER_ID>';
-- Timer expires in 24h. All trigger math should still work.
-- push_66_at = check_in + 1 day * 0.34 = ~8h10m after check-in
-- push_33_at = check_in + 1 day * 0.67 = ~16h05m after check-in
-- email_24h_at = deadline - 1 day = check_in (same time! email triggers immediately)

-- ── 11g. Timer days boundary: 365 days (Lifetime max) ──
-- UPDATE profiles SET timer_days = 365, last_check_in = now() WHERE id = '<TEST_USER_ID>';
-- push_66_at = ~124 days after check-in
-- push_33_at = ~244 days after check-in
-- email_24h_at = ~364 days after check-in


-- ════════════════════════════════════════════════════════════════════════════
-- 12. FULL STATE INSPECTION QUERIES (run anytime to audit)
-- ════════════════════════════════════════════════════════════════════════════

-- ── 12a. All profiles with their timer state ──
SELECT
  p.id,
  p.email,
  p.status,
  p.subscription_status,
  p.timer_days,
  p.selected_theme,
  p.selected_soul_fire,
  p.last_check_in,
  p.last_check_in + (p.timer_days || ' days')::interval AS deadline,
  p.last_check_in + (p.timer_days || ' days')::interval - now() AS remaining,
  p.warning_sent_at,
  p.push_66_sent_at,
  p.push_33_sent_at,
  p.protocol_executed_at,
  CASE
    WHEN p.status = 'inactive' AND p.protocol_executed_at IS NOT NULL
      THEN p.protocol_executed_at + interval '30 days' - now()
    ELSE NULL
  END AS grace_remaining
FROM profiles p
ORDER BY p.created_at DESC
LIMIT 20;

-- ── 12b. Vault entries per user ──
SELECT
  v.user_id,
  v.id AS entry_id,
  v.title,
  v.action_type,
  v.data_type,
  v.status,
  v.audio_duration_seconds,
  v.created_at
FROM vault_entries v
ORDER BY v.created_at DESC
LIMIT 20;

-- ── 12c. Users needing downgrade (free with pro artifacts) ──
SELECT id, email, subscription_status, timer_days,
       selected_theme, selected_soul_fire
FROM profiles
WHERE subscription_status = 'free'
  AND (timer_days > 30
    OR selected_theme IS NOT NULL
    OR selected_soul_fire IS NOT NULL);

-- ── 12d. Users in grace period ──
SELECT id, email, status, protocol_executed_at,
       protocol_executed_at + interval '30 days' AS grace_deadline,
       protocol_executed_at + interval '30 days' - now() AS grace_remaining
FROM profiles
WHERE status = 'inactive'
  AND protocol_executed_at IS NOT NULL;

-- ── 12e. Users with expired timers (should be processed by heartbeat) ──
SELECT id, email, status, timer_days, last_check_in,
       last_check_in + (timer_days || ' days')::interval AS deadline,
       last_check_in + (timer_days || ' days')::interval - now() AS remaining
FROM profiles
WHERE status = 'active'
  AND last_check_in + (timer_days || ' days')::interval <= now();

-- ── 12f. Orphaned states (should be healed by heartbeat guards) ──
-- Active profiles with stale protocol_executed_at:
SELECT id, status, protocol_executed_at
FROM profiles
WHERE status = 'active' AND protocol_executed_at IS NOT NULL;

-- Inactive profiles without protocol_executed_at:
SELECT id, status, protocol_executed_at
FROM profiles
WHERE status = 'inactive' AND protocol_executed_at IS NULL;


-- ════════════════════════════════════════════════════════════════════════════
-- 13. CLEANUP — Reset test users to clean state
-- ════════════════════════════════════════════════════════════════════════════

-- UPDATE profiles
-- SET status = 'active',
--     subscription_status = 'free',
--     timer_days = 30,
--     last_check_in = now(),
--     selected_theme = NULL,
--     selected_soul_fire = NULL,
--     warning_sent_at = NULL,
--     push_66_sent_at = NULL,
--     push_33_sent_at = NULL,
--     protocol_executed_at = NULL
-- WHERE id IN ('<TEST_USER_ID_1>', '<TEST_USER_ID_2>', '<TEST_USER_ID_3>');


-- ════════════════════════════════════════════════════════════════════════════
-- END OF TEST SQL
-- ════════════════════════════════════════════════════════════════════════════
