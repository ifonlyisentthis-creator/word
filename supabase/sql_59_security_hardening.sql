-- ============================================================================
-- AFTERWORD SQL #59 — Security Hardening (Audit Fixes)
--
-- Fixes found during comprehensive security audit:
--
--   1. CRITICAL: Restore missing recurring (Forever Letters) gate on INSERT RLS
--      (Regression from sql_58 which dropped the gate when updating audio policy)
--
--   2. Add pro entry count limit (20) and lifetime entry count limit (30) to
--      INSERT RLS — previously only free (3) was enforced server-side
--
--   3. Add scheduled_at date range enforcement trigger — prevents clients from
--      setting scheduling dates beyond tier limits (free=30d, pro=365d,
--      lifetime=3650d)
--
--   4. Add guard trigger for app_mode on profiles — prevents clients from
--      bypassing update_app_mode() RPC business rules via direct UPDATE
--
--   5. Add INSERT-time guard for grace_until and last_sent_year — prevents
--      clients from setting malicious values on entry creation
--
-- Safe to re-run (all statements are idempotent).
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  1. FIX INSERT RLS — restore recurring gate + add tier entry limits    ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

DROP POLICY IF EXISTS entries_insert_own ON vault_entries;
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
  -- Audio requires Pro/Lifetime
  AND (
    data_type <> 'audio'
    OR EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.subscription_status IN ('pro','lifetime')
    )
  )
  -- Recurring (Forever Letters) requires Pro/Lifetime
  AND (
    COALESCE(entry_mode, 'standard') <> 'recurring'
    OR EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.subscription_status IN ('pro','lifetime')
    )
  )
  -- Tier-based entry count limits
  AND (
    SELECT CASE
      WHEN p.subscription_status = 'lifetime' THEN
        (SELECT count(*) FROM vault_entries ve
         WHERE ve.user_id = auth.uid() AND ve.status = 'active') < 30
      WHEN p.subscription_status = 'pro' THEN
        (SELECT count(*) FROM vault_entries ve
         WHERE ve.user_id = auth.uid() AND ve.status = 'active') < 20
      ELSE
        -- Free: max 3 active text items
        (SELECT count(*) FROM vault_entries ve
         WHERE ve.user_id = auth.uid()
           AND ve.status = 'active'
           AND ve.data_type = 'text') < 3
    END
    FROM profiles p
    WHERE p.id = auth.uid()
  )
);

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  2. ENFORCE scheduled_at date range by subscription tier               ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.guard_scheduled_at()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  sub text;
  max_days int;
BEGIN
  -- Only validate when scheduled_at is set and caller is not service_role
  IF new.scheduled_at IS NULL THEN RETURN new; END IF;
  IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN
    RETURN new;
  END IF;

  SELECT subscription_status INTO sub
  FROM profiles WHERE id = new.user_id;

  IF sub = 'lifetime' THEN
    max_days := 3650;
  ELSIF sub = 'pro' THEN
    max_days := 365;
  ELSE
    max_days := 30;
  END IF;

  IF new.scheduled_at > (now() + (max_days || ' days')::interval) THEN
    RAISE EXCEPTION 'scheduled_at exceeds tier limit (% days)', max_days;
  END IF;

  -- scheduled_at must be in the future (at least 1 hour from now to allow
  -- for clock skew, but not in the past)
  IF new.scheduled_at < now() - interval '1 hour' THEN
    RAISE EXCEPTION 'scheduled_at must be in the future';
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS vault_entries_guard_scheduled_at ON vault_entries;
CREATE TRIGGER vault_entries_guard_scheduled_at
BEFORE INSERT OR UPDATE ON vault_entries
FOR EACH ROW EXECUTE FUNCTION public.guard_scheduled_at();

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  3. GUARD app_mode on profiles — prevent bypassing update_app_mode()   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- 3a. The guard trigger silently reverts app_mode changes from non-service-role
-- callers UNLESS the session variable 'afterword.allow_app_mode_change' is set
-- to 'true'.  The update_app_mode() RPC sets this variable before its UPDATE.
CREATE OR REPLACE FUNCTION public.guard_app_mode()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF new.app_mode IS DISTINCT FROM old.app_mode THEN
    -- service_role can always change app_mode (heartbeat, Edge Functions)
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN
      RETURN new;
    END IF;
    -- Allow if the caller is the update_app_mode() RPC (sets session flag)
    IF COALESCE(current_setting('afterword.allow_app_mode_change', true), '') = 'true' THEN
      RETURN new;
    END IF;
    -- Block direct client UPDATE — silently revert
    new.app_mode := old.app_mode;
  END IF;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS profiles_guard_app_mode ON profiles;
CREATE TRIGGER profiles_guard_app_mode
BEFORE UPDATE ON profiles
FOR EACH ROW EXECUTE FUNCTION public.guard_app_mode();

-- 3b. Re-create update_app_mode() to set the session flag before UPDATE
CREATE OR REPLACE FUNCTION public.update_app_mode(p_mode text)
RETURNS profiles
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  result profiles;
  entry_count int;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF p_mode NOT IN ('vault', 'scheduled') THEN
    RAISE EXCEPTION 'invalid mode: %', p_mode;
  END IF;

  -- Block switching if any entries exist in non-cleared states
  SELECT count(*) INTO entry_count
  FROM vault_entries
  WHERE user_id = auth.uid()
    AND status IN ('active', 'sending', 'sent');

  IF entry_count > 0 THEN
    RAISE EXCEPTION 'cannot switch mode while vaults are active or in grace period';
  END IF;

  -- Set session flag so guard_app_mode trigger allows this UPDATE
  PERFORM set_config('afterword.allow_app_mode_change', 'true', true);

  UPDATE profiles
  SET app_mode = p_mode,
      status = 'active',
      protocol_executed_at = NULL,
      warning_sent_at = NULL,
      last_check_in = now()
  WHERE id = auth.uid()
  RETURNING * INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.update_app_mode(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_app_mode(text) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  4. GUARD grace_until + last_sent_year on INSERT                       ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
-- The existing guard_entry_mode trigger protects these columns on UPDATE,
-- but INSERT is unguarded.  A malicious client could set last_sent_year to
-- 9999 (preventing delivery) or grace_until to NULL (preventing cleanup).

CREATE OR REPLACE FUNCTION public.guard_insert_server_columns()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN
    RETURN new;
  END IF;

  -- last_sent_year must be NULL on insert (heartbeat sets it after first send)
  IF new.last_sent_year IS NOT NULL THEN
    new.last_sent_year := NULL;
  END IF;

  -- sent_at must be NULL on insert (heartbeat sets it when sending)
  IF new.sent_at IS NOT NULL THEN
    new.sent_at := NULL;
  END IF;

  -- grace_until: for scheduled/standard entries, must be scheduled_at + 30 days
  -- or NULL if no scheduled_at.  Don't allow arbitrary values.
  IF new.scheduled_at IS NOT NULL AND COALESCE(new.entry_mode, 'standard') <> 'recurring' THEN
    new.grace_until := new.scheduled_at + interval '30 days';
  ELSE
    -- Recurring entries and entries without scheduled_at: grace_until should be NULL
    -- The heartbeat will set it appropriately after sending
    new.grace_until := NULL;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS vault_entries_guard_insert_columns ON vault_entries;
CREATE TRIGGER vault_entries_guard_insert_columns
BEFORE INSERT ON vault_entries
FOR EACH ROW EXECUTE FUNCTION public.guard_insert_server_columns();

-- ============================================================================
-- END OF SQL #59
-- ============================================================================
