-- ============================================================================
-- AFTERWORD SQL #61 — Admin Panel (RPCs + Tables)
--
-- Creates the admin infrastructure for the Afterword admin dashboard:
--
--   1.  admin_users table — tracks who has admin access
--   2.  heartbeat_runs table — stores heartbeat execution logs
--   3.  is_admin() helper — checks admin status for the current user
--   4.  admin_check() — simple wrapper exposing is_admin() as an RPC
--   5.  admin_get_dashboard_stats() — aggregate dashboard statistics
--   6.  admin_list_users() — paginated user list with search/filter
--   7.  admin_get_user_detail() — full profile + entries + devices + tombstones
--   8.  admin_list_entries() — paginated entry list with filters
--   9.  admin_delete_entry() — hard-delete a single vault entry
--  10.  admin_ban_user() — archive a user (soft ban)
--  11.  admin_unban_user() — reactivate a banned user
--  12.  admin_delete_user() — hard-delete from auth.users (CASCADE)
--  13.  admin_list_heartbeat_runs() — paginated heartbeat run history
--  14.  admin_add_admin() — grant admin to a user by email
--  15.  admin_remove_admin() — revoke admin (self-removal blocked)
--  16.  admin_list_admins() — list all admin users
--
-- Safe to re-run (all statements are idempotent).
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  1. ADMIN_USERS TABLE                                                  ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

DROP TABLE IF EXISTS admin_users;
CREATE TABLE admin_users (
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  email      text        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id)
);

ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- Only service_role can read/write admin_users (no client access)
DROP POLICY IF EXISTS admin_users_service_role ON admin_users;
CREATE POLICY admin_users_service_role ON admin_users
  USING (
    COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role'
  )
  WITH CHECK (
    COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role'
  );

CREATE INDEX IF NOT EXISTS idx_admin_users_email ON admin_users (email);

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  2. HEARTBEAT_RUNS TABLE                                               ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

DROP TABLE IF EXISTS heartbeat_runs;
CREATE TABLE heartbeat_runs (
  id                    uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at            timestamptz    NOT NULL DEFAULT now(),
  completed_at          timestamptz,
  runtime_seconds       numeric(10,1),
  profiles_processed    int            DEFAULT 0,
  entries_seen          int            DEFAULT 0,
  emails_sent           int            DEFAULT 0,
  emails_failed         int            DEFAULT 0,
  pushes_sent           int            DEFAULT 0,
  pushes_failed         int            DEFAULT 0,
  entries_delivered      int            DEFAULT 0,
  entries_destroyed      int            DEFAULT 0,
  entries_cleaned_up     int            DEFAULT 0,
  bots_cleaned_up        int            DEFAULT 0,
  recurring_sent         int            DEFAULT 0,
  scheduled_delivered    int            DEFAULT 0,
  downgrades_processed   int            DEFAULT 0,
  rc_verifications       int            DEFAULT 0,
  errors                jsonb          NOT NULL DEFAULT '[]'::jsonb,
  warnings              jsonb          NOT NULL DEFAULT '[]'::jsonb,
  cleanup_stats         jsonb          NOT NULL DEFAULT '{}'::jsonb,
  resend_quota_exhausted boolean       NOT NULL DEFAULT false,
  exit_reason           text           NOT NULL DEFAULT 'completed',
  created_at            timestamptz    NOT NULL DEFAULT now()
);

ALTER TABLE heartbeat_runs ENABLE ROW LEVEL SECURITY;

-- service_role can INSERT and SELECT heartbeat_runs
DROP POLICY IF EXISTS heartbeat_runs_service_insert ON heartbeat_runs;
CREATE POLICY heartbeat_runs_service_insert ON heartbeat_runs
  FOR INSERT
  WITH CHECK (
    COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role'
  );

DROP POLICY IF EXISTS heartbeat_runs_service_select ON heartbeat_runs;
CREATE POLICY heartbeat_runs_service_select ON heartbeat_runs
  FOR SELECT
  USING (
    COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role'
  );

CREATE INDEX IF NOT EXISTS idx_heartbeat_runs_started_at
  ON heartbeat_runs (started_at DESC);

CREATE INDEX IF NOT EXISTS idx_heartbeat_runs_created_at
  ON heartbeat_runs (created_at DESC);

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  3. is_admin() HELPER                                                  ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM admin_users WHERE user_id = auth.uid()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM public;
REVOKE ALL ON FUNCTION public.is_admin() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  4. admin_check() — simple wrapper                                     ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_check()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
  RETURN public.is_admin();
END;
$$;

REVOKE ALL ON FUNCTION public.admin_check() FROM public;
REVOKE ALL ON FUNCTION public.admin_check() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_check() TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  5. admin_get_dashboard_stats()                                        ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_get_dashboard_stats()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT json_build_object(
    -- User counts
    'total_users',        (SELECT count(*) FROM profiles),
    'active_users',       (SELECT count(*) FROM profiles WHERE status = 'active'),
    'inactive_users',     (SELECT count(*) FROM profiles WHERE status IN ('inactive', 'archived')),
    'new_today',          (SELECT count(*) FROM profiles WHERE created_at >= date_trunc('day', now())),
    'new_this_week',      (SELECT count(*) FROM profiles WHERE created_at >= date_trunc('week', now())),
    'new_this_month',     (SELECT count(*) FROM profiles WHERE created_at >= date_trunc('month', now())),

    -- Subscription breakdown
    'sub_free',           (SELECT count(*) FROM profiles WHERE subscription_status = 'free'),
    'sub_pro',            (SELECT count(*) FROM profiles WHERE subscription_status = 'pro'),
    'sub_lifetime',       (SELECT count(*) FROM profiles WHERE subscription_status = 'lifetime'),

    -- Entry counts
    'total_entries',      (SELECT count(*) FROM vault_entries),
    'active_entries',     (SELECT count(*) FROM vault_entries WHERE status = 'active'),
    'sent_entries',       (SELECT count(*) FROM vault_entries WHERE status = 'sent'),

    -- Entry type breakdown
    'entries_text',       (SELECT count(*) FROM vault_entries WHERE data_type = 'text'),
    'entries_audio',      (SELECT count(*) FROM vault_entries WHERE data_type = 'audio'),

    -- Entry mode breakdown
    'entries_standard',   (SELECT count(*) FROM vault_entries WHERE COALESCE(entry_mode, 'standard') = 'standard'),
    'entries_recurring',  (SELECT count(*) FROM vault_entries WHERE entry_mode = 'recurring'),

    -- Activity
    'entries_sent_today', (SELECT count(*) FROM vault_entries WHERE sent_at >= date_trunc('day', now())),

    -- App mode breakdown
    'vault_mode_users',     (SELECT count(*) FROM profiles WHERE COALESCE(app_mode, 'vault') = 'vault'),
    'scheduled_mode_users', (SELECT count(*) FROM profiles WHERE app_mode = 'scheduled')
  ) INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_dashboard_stats() FROM public;
REVOKE ALL ON FUNCTION public.admin_get_dashboard_stats() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_get_dashboard_stats() TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  6. admin_list_users()                                                 ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_list_users(
  p_search       text DEFAULT NULL,
  p_status       text DEFAULT NULL,
  p_subscription text DEFAULT NULL,
  p_limit        int  DEFAULT 50,
  p_offset       int  DEFAULT 0
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
  total_count bigint;
  users_arr  json;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- Get total count with filters
  SELECT count(*) INTO total_count
  FROM profiles p
  WHERE (p_search IS NULL OR p.email ILIKE '%' || p_search || '%' OR p.sender_name ILIKE '%' || p_search || '%')
    AND (p_status IS NULL OR p.status = p_status)
    AND (p_subscription IS NULL OR p.subscription_status = p_subscription);

  -- Get paginated user list
  SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json) INTO users_arr
  FROM (
    SELECT
      p.id,
      p.email,
      p.sender_name,
      p.status,
      p.subscription_status,
      p.app_mode,
      p.last_check_in,
      p.timer_days,
      p.created_at,
      p.updated_at,
      (SELECT count(*) FROM vault_entries ve WHERE ve.user_id = p.id AND ve.status = 'active') AS active_entry_count,
      (SELECT count(*) FROM vault_entries ve WHERE ve.user_id = p.id) AS total_entry_count,
      (SELECT count(*) FROM push_devices pd WHERE pd.user_id = p.id) AS device_count
    FROM profiles p
    WHERE (p_search IS NULL OR p.email ILIKE '%' || p_search || '%' OR p.sender_name ILIKE '%' || p_search || '%')
      AND (p_status IS NULL OR p.status = p_status)
      AND (p_subscription IS NULL OR p.subscription_status = p_subscription)
    ORDER BY p.created_at DESC
    LIMIT p_limit
    OFFSET p_offset
  ) t;

  RETURN json_build_object(
    'users', users_arr,
    'total', total_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_users(text, text, text, int, int) FROM public;
REVOKE ALL ON FUNCTION public.admin_list_users(text, text, text, int, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_users(text, text, text, int, int) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  7. admin_get_user_detail()                                            ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_get_user_detail(p_user_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result       json;
  profile_data json;
  entries_data json;
  devices_data json;
  tombs_data   json;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- Profile: all non-sensitive columns (exclude hmac_key_encrypted, key_backup_encrypted)
  SELECT row_to_json(t) INTO profile_data
  FROM (
    SELECT
      p.id,
      p.email,
      p.sender_name,
      p.status,
      p.subscription_status,
      p.app_mode,
      p.last_check_in,
      p.timer_days,
      p.selected_theme,
      p.selected_soul_fire,
      p.warning_sent_at,
      p.push_66_sent_at,
      p.push_33_sent_at,
      p.protocol_executed_at,
      p.last_entry_at,
      p.had_vault_activity,
      p.downgrade_email_pending,
      p.created_at,
      p.updated_at
    FROM profiles p
    WHERE p.id = p_user_id
  ) t;

  IF profile_data IS NULL THEN
    RAISE EXCEPTION 'user not found';
  END IF;

  -- Entries: metadata only — NO payload_encrypted, NO recipient_email_encrypted,
  -- NO data_key_encrypted, NO hmac_signature
  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.created_at DESC), '[]'::json) INTO entries_data
  FROM (
    SELECT
      ve.id,
      ve.user_id,
      ve.title,
      ve.action_type,
      ve.data_type,
      ve.status,
      ve.entry_mode,
      ve.is_zero_knowledge,
      ve.scheduled_at,
      ve.grace_until,
      ve.sent_at,
      ve.last_sent_year,
      ve.audio_file_path,
      ve.audio_duration_seconds,
      ve.created_at,
      ve.updated_at
    FROM vault_entries ve
    WHERE ve.user_id = p_user_id
  ) t;

  -- Devices: NO fcm_token
  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.last_seen_at DESC), '[]'::json) INTO devices_data
  FROM (
    SELECT
      pd.id,
      pd.user_id,
      pd.platform,
      pd.last_seen_at,
      pd.created_at,
      pd.updated_at
    FROM push_devices pd
    WHERE pd.user_id = p_user_id
  ) t;

  -- Tombstones
  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.expired_at DESC), '[]'::json) INTO tombs_data
  FROM (
    SELECT
      vt.vault_entry_id,
      vt.user_id,
      vt.sender_name,
      vt.sent_at,
      vt.expired_at,
      vt.created_at
    FROM vault_entry_tombstones vt
    WHERE vt.user_id = p_user_id
  ) t;

  RETURN json_build_object(
    'profile',    profile_data,
    'entries',    entries_data,
    'devices',    devices_data,
    'tombstones', tombs_data
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_user_detail(uuid) FROM public;
REVOKE ALL ON FUNCTION public.admin_get_user_detail(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_get_user_detail(uuid) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  8. admin_list_entries()                                               ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_list_entries(
  p_status      text DEFAULT NULL,
  p_entry_mode  text DEFAULT NULL,
  p_data_type   text DEFAULT NULL,
  p_action_type text DEFAULT NULL,
  p_limit       int  DEFAULT 50,
  p_offset      int  DEFAULT 0
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result      json;
  total_count bigint;
  entries_arr json;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- Total count with filters
  SELECT count(*) INTO total_count
  FROM vault_entries ve
  WHERE (p_status IS NULL OR ve.status = p_status)
    AND (p_entry_mode IS NULL OR COALESCE(ve.entry_mode, 'standard') = p_entry_mode)
    AND (p_data_type IS NULL OR ve.data_type = p_data_type)
    AND (p_action_type IS NULL OR ve.action_type = p_action_type);

  -- Paginated entries joined with profiles for user context
  SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json) INTO entries_arr
  FROM (
    SELECT
      ve.id,
      ve.user_id,
      ve.title,
      ve.action_type,
      ve.data_type,
      ve.status,
      ve.entry_mode,
      ve.is_zero_knowledge,
      ve.scheduled_at,
      ve.grace_until,
      ve.sent_at,
      ve.last_sent_year,
      ve.audio_file_path,
      ve.audio_duration_seconds,
      ve.created_at,
      ve.updated_at,
      p.email       AS user_email,
      p.sender_name AS user_sender_name
    FROM vault_entries ve
    JOIN profiles p ON p.id = ve.user_id
    WHERE (p_status IS NULL OR ve.status = p_status)
      AND (p_entry_mode IS NULL OR COALESCE(ve.entry_mode, 'standard') = p_entry_mode)
      AND (p_data_type IS NULL OR ve.data_type = p_data_type)
      AND (p_action_type IS NULL OR ve.action_type = p_action_type)
    ORDER BY ve.created_at DESC
    LIMIT p_limit
    OFFSET p_offset
  ) t;

  RETURN json_build_object(
    'entries', entries_arr,
    'total',  total_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_entries(text, text, text, text, int, int) FROM public;
REVOKE ALL ON FUNCTION public.admin_list_entries(text, text, text, text, int, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_entries(text, text, text, text, int, int) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  9. admin_delete_entry()                                               ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_delete_entry(p_entry_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  DELETE FROM vault_entries WHERE id = p_entry_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'entry not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_entry(uuid) FROM public;
REVOKE ALL ON FUNCTION public.admin_delete_entry(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_entry(uuid) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  10. admin_ban_user()                                                  ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_ban_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  UPDATE profiles SET status = 'archived' WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_ban_user(uuid) FROM public;
REVOKE ALL ON FUNCTION public.admin_ban_user(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_ban_user(uuid) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  11. admin_unban_user()                                                ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_unban_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  UPDATE profiles
  SET status = 'active',
      last_check_in = now()
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_unban_user(uuid) FROM public;
REVOKE ALL ON FUNCTION public.admin_unban_user(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_unban_user(uuid) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  12. admin_delete_user()                                               ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_delete_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- Prevent admins from deleting themselves
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'cannot delete yourself';
  END IF;

  -- Delete from auth.users — ON DELETE CASCADE handles profiles,
  -- vault_entries, push_devices, tombstones, admin_users
  DELETE FROM auth.users WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_user(uuid) FROM public;
REVOKE ALL ON FUNCTION public.admin_delete_user(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_user(uuid) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  13. admin_list_heartbeat_runs()                                       ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_list_heartbeat_runs(
  p_limit  int DEFAULT 20,
  p_offset int DEFAULT 0
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result      json;
  total_count bigint;
  runs_arr    json;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT count(*) INTO total_count FROM heartbeat_runs;

  SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json) INTO runs_arr
  FROM (
    SELECT
      hr.id,
      hr.started_at,
      hr.completed_at,
      hr.runtime_seconds,
      hr.profiles_processed,
      hr.entries_seen,
      hr.emails_sent,
      hr.emails_failed,
      hr.pushes_sent,
      hr.pushes_failed,
      hr.entries_delivered,
      hr.entries_destroyed,
      hr.entries_cleaned_up,
      hr.bots_cleaned_up,
      hr.recurring_sent,
      hr.scheduled_delivered,
      hr.downgrades_processed,
      hr.rc_verifications,
      hr.errors,
      hr.warnings,
      hr.cleanup_stats,
      hr.resend_quota_exhausted,
      hr.exit_reason,
      hr.created_at
    FROM heartbeat_runs hr
    ORDER BY hr.started_at DESC
    LIMIT p_limit
    OFFSET p_offset
  ) t;

  RETURN json_build_object(
    'runs',  runs_arr,
    'total', total_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_heartbeat_runs(int, int) FROM public;
REVOKE ALL ON FUNCTION public.admin_list_heartbeat_runs(int, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_heartbeat_runs(int, int) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  14. admin_add_admin()                                                 ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_add_admin(p_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  target_uid uuid;
  target_email text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- Look up the user in auth.users by email
  SELECT id, email INTO target_uid, target_email
  FROM auth.users
  WHERE email = lower(trim(p_email));

  IF target_uid IS NULL THEN
    RAISE EXCEPTION 'user not found with email: %', p_email;
  END IF;

  INSERT INTO admin_users (user_id, email)
  VALUES (target_uid, target_email)
  ON CONFLICT (user_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_add_admin(text) FROM public;
REVOKE ALL ON FUNCTION public.admin_add_admin(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_add_admin(text) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  15. admin_remove_admin()                                              ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_remove_admin(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- Prevent self-removal
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'cannot remove yourself as admin';
  END IF;

  DELETE FROM admin_users WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_remove_admin(uuid) FROM public;
REVOKE ALL ON FUNCTION public.admin_remove_admin(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_remove_admin(uuid) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  16. admin_list_admins()                                               ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_list_admins()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.created_at), '[]'::json) INTO result
  FROM (
    SELECT
      au.user_id,
      au.email,
      au.created_at
    FROM admin_users au
  ) t;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_admins() FROM public;
REVOKE ALL ON FUNCTION public.admin_list_admins() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_admins() TO authenticated;

-- ============================================================================
-- END OF SQL #61
-- ============================================================================
