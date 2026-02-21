-- ============================================================================
-- AFTERWORD v40 — Server-side 12-hour cooldown guard on update_check_in
-- Run this in Supabase SQL Editor.
--
-- Defence-in-depth: the client already enforces a 12-hour cooldown on Soul
-- Fire presses, but this migration adds a server-side guard so that even
-- direct REST API calls cannot spam last_check_in resets.
--
-- Behaviour:
--   - If last_check_in is within 12 hours AND it is NOT the very first
--     check-in after account creation (60s tolerance), the RPC returns the
--     current profile row unchanged — no UPDATE is executed.
--   - update_timer_days is NOT affected (separate RPC; timer adjustments
--     always reset the timer as intended).
--   - heartbeat.py writes via service_role direct UPDATEs, not this RPC,
--     so they are unaffected.
-- ============================================================================

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
  current_last_check_in timestamptz;
  profile_created_at timestamptz;
BEGIN
  IF auth.uid() <> user_id THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT subscription_status, timer_days, last_check_in, created_at
  INTO sub, effective_timer, current_last_check_in, profile_created_at
  FROM profiles
  WHERE id = user_id;

  IF sub IS NULL THEN
    RAISE EXCEPTION 'profile not found';
  END IF;

  -- ── Server-side 12-hour cooldown ──
  -- Allow the write if:
  --   (a) last_check_in is NULL (should not happen, but safe), OR
  --   (b) this is the first real check-in (last_check_in ≈ created_at within 60s), OR
  --   (c) 12+ hours have elapsed since last_check_in
  IF current_last_check_in IS NOT NULL
     AND abs(extract(epoch FROM current_last_check_in - profile_created_at)) > 60
     AND now() - current_last_check_in < interval '12 hours'
  THEN
    -- Cooldown active: return current profile without writing
    SELECT * INTO result FROM profiles WHERE id = user_id;
    RETURN result;
  END IF;

  -- ── Subscription-tier timer clamping ──
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

-- ============================================================================
-- END OF v40 SQL
-- ============================================================================
