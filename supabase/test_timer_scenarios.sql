-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Test Scenarios for Profile ID: 6a082072-3304-47a3-b13f-1430e52839a9     ║
-- ║  1. Timer at 0 minutes remaining (expired)                             ║
-- ║  2. Grace period at 0 minutes (grace ended)                           ║
-- ║  3. 24-hour email warning trigger                                      ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. TIMER AT 0 MINUTES REMAINING (EXPIRED)
--    - last_check_in + timer_days = deadline (5 minutes ago)
--    - protocol_executed_at is NULL (not yet executed)
--    - status should be 'expired'
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE profiles
SET 
  timer_days = 30,
  created_at = NOW() - INTERVAL '35 days',
  last_check_in = NOW() - INTERVAL '30 days' - INTERVAL '5 minutes',  -- 30 days + 5 min ago
  grace_period_until = NOW() + INTERVAL '24 hours',
  protocol_executed_at = NULL,
  status = 'expired',
  subscription_status = 'pro',
  selected_theme = 'velvetAbyss',
  selected_soul_fire = 'infinityWell'
WHERE id = '6a082072-3304-47a3-b13f-1430e52839a9';

-- Verify the state
SELECT 
  id,
  timer_days,
  created_at,
  last_check_in,
  last_check_in + (timer_days || ' days')::INTERVAL AS calculated_deadline,
  grace_period_until,
  protocol_executed_at,
  status,
  subscription_status,
  selected_theme,
  selected_soul_fire,
  -- Time calculations that heartbeat.py uses
  EXTRACT(EPOCH FROM ((last_check_in + (timer_days || ' days')::INTERVAL) - NOW())) / 60 AS minutes_remaining,
  CASE 
    WHEN (last_check_in + (timer_days || ' days')::INTERVAL) < NOW() THEN 'EXPIRED'
    WHEN (last_check_in + (timer_days || ' days')::INTERVAL) < NOW() + INTERVAL '24 hours' THEN 'WARNING'
    ELSE 'ACTIVE'
  END AS timer_state
FROM profiles 
WHERE id = '6a082072-3304-47a3-b13f-1430e52839a9';

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. GRACE PERIOD AT 0 MINUTES (GRACE ENDED)
--    - last_check_in + timer_days = deadline (expired yesterday)
--    - grace_period_until is exactly now or in the past
--    - protocol_executed_at is NULL (should trigger execution)
--    - status should still be 'expired' until heartbeat runs
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE profiles
SET 
  timer_days = 30,
  created_at = NOW() - INTERVAL '35 days',
  last_check_in = NOW() - INTERVAL '55 hours',    -- Expired 25 hours ago (30d - 55h = -25h)
  grace_period_until = NOW() - INTERVAL '1 minute',  -- Grace ended 1 min ago
  protocol_executed_at = NULL,
  status = 'expired',
  subscription_status = 'pro',
  selected_theme = 'velvetAbyss',
  selected_soul_fire = 'infinityWell'
WHERE id = '6a082072-3304-47a3-b13f-1430e52839a9';

-- Verify the state
SELECT 
  id,
  timer_days,
  created_at,
  last_check_in,
  last_check_in + (timer_days || ' days')::INTERVAL AS calculated_deadline,
  grace_period_until,
  protocol_executed_at,
  status,
  subscription_status,
  selected_theme,
  selected_soul_fire,
  -- Time calculations
  EXTRACT(EPOCH FROM ((last_check_in + (timer_days || ' days')::INTERVAL) - NOW())) / 60 AS minutes_remaining,
  EXTRACT(EPOCH FROM (grace_period_until - NOW())) / 60 AS grace_minutes_remaining,
  CASE 
    WHEN grace_period_until < NOW() THEN 'GRACE_ENDED_SHOULD_EXECUTE'
    WHEN (last_check_in + (timer_days || ' days')::INTERVAL) < NOW() AND grace_period_until > NOW() THEN 'IN_GRACE_PERIOD'
    WHEN (last_check_in + (timer_days || ' days')::INTERVAL) < NOW() THEN 'EXPIRED'
    WHEN (last_check_in + (timer_days || ' days')::INTERVAL) < NOW() + INTERVAL '24 hours' THEN 'WARNING'
    ELSE 'ACTIVE'
  END AS timer_state
FROM profiles 
WHERE id = '6a082072-3304-47a3-b13f-1430e52839a9';

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. 24-HOUR EMAIL WARNING TRIGGER
--    - last_check_in + timer_days = deadline (exactly 24h from now)
--    - Should trigger warning email on next heartbeat run
--    - No email sent yet (last_warning_email_at is NULL or older than 23h)
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE profiles
SET 
  timer_days = 30,
  created_at = NOW() - INTERVAL '5 days',
  last_check_in = NOW() - INTERVAL '6 days',    -- 6 days ago, so deadline is 24h from now
  grace_period_until = NOW() + INTERVAL '48 hours',
  protocol_executed_at = NULL,
  status = 'active',
  subscription_status = 'pro',
  selected_theme = 'obsidianPrism',
  selected_soul_fire = 'phantomPulse',
  last_warning_email_at = NULL  -- No warning sent yet
WHERE id = '6a082072-3304-47a3-b13f-1430e52839a9';

-- Verify the state
SELECT 
  id,
  timer_days,
  created_at,
  last_check_in,
  last_check_in + (timer_days || ' days')::INTERVAL AS calculated_deadline,
  grace_period_until,
  protocol_executed_at,
  status,
  subscription_status,
  selected_theme,
  selected_soul_fire,
  last_warning_email_at,
  -- Time calculations that heartbeat.py uses for 24h warning
  EXTRACT(EPOCH FROM ((last_check_in + (timer_days || ' days')::INTERVAL) - NOW())) / 60 AS minutes_remaining,
  EXTRACT(EPOCH FROM ((last_check_in + (timer_days || ' days')::INTERVAL) - NOW())) / 3600 AS hours_remaining,
  CASE 
    WHEN ABS(EXTRACT(EPOCH FROM ((last_check_in + (timer_days || ' days')::INTERVAL) - NOW())) / 3600 - 24) < 0.5 THEN 'WARNING_TRIGGER_24H'
    WHEN (last_check_in + (timer_days || ' days')::INTERVAL) < NOW() THEN 'EXPIRED'
    WHEN (last_check_in + (timer_days || ' days')::INTERVAL) < NOW() + INTERVAL '24 hours' THEN 'WARNING_WINDOW'
    ELSE 'ACTIVE'
  END AS timer_state,
  CASE 
    WHEN last_warning_email_at IS NULL THEN 'NO_WARNING_SENT'
    WHEN last_warning_email_at < NOW() - INTERVAL '23 hours' THEN 'CAN_SEND_WARNING'
    ELSE 'RECENT_WARNING_SENT'
  END AS email_state
FROM profiles 
WHERE id = '6a082072-3304-47a3-b13f-1430e52839a9';

-- ═══════════════════════════════════════════════════════════════════════════
-- BONUS: Test that heartbeat can find this profile in its batch query
-- ═══════════════════════════════════════════════════════════════════════════

-- Simulate heartbeat's batch query (profiles needing processing)
SELECT 
  id,
  status,
  last_check_in,
  last_check_in + (timer_days || ' days')::INTERVAL AS calculated_deadline,
  grace_period_until,
  protocol_executed_at,
  last_warning_email_at,
  CASE 
    WHEN (last_check_in + (timer_days || ' days')::INTERVAL) < NOW() AND grace_period_until < NOW() AND protocol_executed_at IS NULL THEN 'NEEDS_EXECUTION'
    WHEN ABS(EXTRACT(EPOCH FROM ((last_check_in + (timer_days || ' days')::INTERVAL) - NOW())) / 3600 - 24) < 0.5 
         AND (last_warning_email_at IS NULL OR last_warning_email_at < NOW() - INTERVAL '23 hours') 
         THEN 'NEEDS_24H_WARNING'
    WHEN (last_check_in + (timer_days || ' days')::INTERVAL) < NOW() AND grace_period_until > NOW() THEN 'IN_GRACE_PERIOD'
    WHEN (last_check_in + (timer_days || ' days')::INTERVAL) < NOW() THEN 'EXPIRED'
    ELSE 'ACTIVE'
  END AS heartbeat_action
FROM profiles 
WHERE id = '6a082072-3304-47a3-b13f-1430e52839a9'
  AND (
    -- Needs execution (grace ended)
    ((last_check_in + (timer_days || ' days')::INTERVAL) < NOW() AND grace_period_until < NOW() AND protocol_executed_at IS NULL)
    OR
    -- Needs 24h warning
    (ABS(EXTRACT(EPOCH FROM ((last_check_in + (timer_days || ' days')::INTERVAL) - NOW())) / 3600 - 24) < 0.5 
     AND (last_warning_email_at IS NULL OR last_warning_email_at < NOW() - INTERVAL '23 hours'))
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- CLEANUP: Reset to safe state after testing
-- ═══════════════════════════════════════════════════════════════════════════

/*
-- Uncomment to reset after testing
UPDATE profiles
SET 
  timer_days = 30,
  created_at = NOW(),
  last_check_in = NOW(),
  grace_period_until = NOW() + INTERVAL '54 days',
  protocol_executed_at = NULL,
  status = 'active',
  subscription_status = 'pro',
  selected_theme = 'oledVoid',
  selected_soul_fire = 'etherealOrb',
  last_warning_email_at = NULL
WHERE id = '6a082072-3304-47a3-b13f-1430e52839a9';
*/
