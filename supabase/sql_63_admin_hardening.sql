-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  sql_63 — Admin panel hardening                                        ║
-- ║  Fixes: self-ban, p_limit caps, search_path, last-admin guard,        ║
-- ║         clear-all confirmation, self-delete on ban.                    ║
-- ║  Safe to re-run (all CREATE OR REPLACE).                               ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. is_admin() — pin search_path
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. admin_check() — pin search_path
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_check()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.is_admin();
END;
$$;

REVOKE ALL ON FUNCTION public.admin_check() FROM public;
REVOKE ALL ON FUNCTION public.admin_check() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_check() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. admin_get_dashboard_stats() — pin search_path
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_get_dashboard_stats()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result json;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT json_build_object(
    'total_users',        (SELECT count(*) FROM profiles),
    'active_users',       (SELECT count(*) FROM profiles WHERE status = 'active'),
    'inactive_users',     (SELECT count(*) FROM profiles WHERE status IN ('inactive', 'archived')),
    'new_today',          (SELECT count(*) FROM profiles WHERE created_at >= date_trunc('day', now())),
    'new_this_week',      (SELECT count(*) FROM profiles WHERE created_at >= date_trunc('week', now())),
    'new_this_month',     (SELECT count(*) FROM profiles WHERE created_at >= date_trunc('month', now())),
    'sub_free',           (SELECT count(*) FROM profiles WHERE subscription_status = 'free'),
    'sub_pro',            (SELECT count(*) FROM profiles WHERE subscription_status = 'pro'),
    'sub_lifetime',       (SELECT count(*) FROM profiles WHERE subscription_status = 'lifetime'),
    'total_entries',      (SELECT count(*) FROM vault_entries),
    'active_entries',     (SELECT count(*) FROM vault_entries WHERE status = 'active'),
    'sent_entries',       (SELECT count(*) FROM vault_entries WHERE status = 'sent'),
    'entries_text',       (SELECT count(*) FROM vault_entries WHERE data_type = 'text'),
    'entries_audio',      (SELECT count(*) FROM vault_entries WHERE data_type = 'audio'),
    'entries_standard',   (SELECT count(*) FROM vault_entries WHERE COALESCE(entry_mode, 'standard') = 'standard'),
    'entries_recurring',  (SELECT count(*) FROM vault_entries WHERE entry_mode = 'recurring'),
    'entries_sent_today', (SELECT count(*) FROM vault_entries WHERE sent_at >= date_trunc('day', now())),
    'vault_mode_users',     (SELECT count(*) FROM profiles WHERE COALESCE(app_mode, 'vault') = 'vault'),
    'scheduled_mode_users', (SELECT count(*) FROM profiles WHERE app_mode = 'scheduled'),
    'no_vault_activity',    (SELECT count(*) FROM profiles WHERE had_vault_activity = false)
  ) INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_dashboard_stats() FROM public;
REVOKE ALL ON FUNCTION public.admin_get_dashboard_stats() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_get_dashboard_stats() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. admin_list_users() — pin search_path + cap p_limit at 100
-- ═══════════════════════════════════════════════════════════════════════════

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
SET search_path = public
AS $$
DECLARE
  result      json;
  total_count bigint;
  users_arr   json;
  safe_limit  int := LEAST(GREATEST(p_limit, 1), 100);
  safe_offset int := GREATEST(p_offset, 0);
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT count(*) INTO total_count
  FROM profiles p
  WHERE (p_search IS NULL OR (
    p.email ILIKE '%' || p_search || '%' OR
    p.sender_name ILIKE '%' || p_search || '%'
  ))
  AND (
    p_status IS NULL
    OR (p_status = 'grace' AND (
      -- Guardian: profile-level grace (protocol fired, inactive, within 30 days)
      (COALESCE(p.app_mode, 'vault') = 'vault'
       AND p.status IN ('inactive', 'archived')
       AND p.protocol_executed_at IS NOT NULL
       AND p.protocol_executed_at + interval '30 days' > now())
      OR
      -- Time Capsule: has entries with active grace_until
      EXISTS (SELECT 1 FROM vault_entries ve
              WHERE ve.user_id = p.id AND ve.status = 'sent'
              AND ve.grace_until IS NOT NULL AND ve.grace_until > now())
    ))
    OR (p_status = 'new_today' AND p.created_at >= date_trunc('day', now()))
    OR (p_status = 'no_vault' AND p.had_vault_activity = false)
    OR (p_status NOT IN ('grace', 'new_today', 'no_vault') AND p.status = p_status)
  )
  AND (p_subscription IS NULL OR p.subscription_status = p_subscription);

  SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json) INTO users_arr
  FROM (
    SELECT
      p.id,
      p.email,
      p.sender_name,
      p.status,
      p.subscription_status,
      p.app_mode,
      p.timer_days,
      p.last_check_in,
      p.warning_sent_at,
      p.protocol_executed_at,
      p.created_at,
      (SELECT count(*) FROM vault_entries ve WHERE ve.user_id = p.id) AS entry_count
    FROM profiles p
    WHERE (p_search IS NULL OR (
      p.email ILIKE '%' || p_search || '%' OR
      p.sender_name ILIKE '%' || p_search || '%'
    ))
    AND (
      p_status IS NULL
      OR (p_status = 'grace' AND (
        (COALESCE(p.app_mode, 'vault') = 'vault'
         AND p.status IN ('inactive', 'archived')
         AND p.protocol_executed_at IS NOT NULL
         AND p.protocol_executed_at + interval '30 days' > now())
        OR
        EXISTS (SELECT 1 FROM vault_entries ve
                WHERE ve.user_id = p.id AND ve.status = 'sent'
                AND ve.grace_until IS NOT NULL AND ve.grace_until > now())
      ))
      OR (p_status = 'new_today' AND p.created_at >= date_trunc('day', now()))
      OR (p_status = 'no_vault' AND p.had_vault_activity = false)
      OR (p_status NOT IN ('grace', 'new_today', 'no_vault') AND p.status = p_status)
    )
    AND (p_subscription IS NULL OR p.subscription_status = p_subscription)
    ORDER BY p.created_at DESC
    LIMIT safe_limit
    OFFSET safe_offset
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

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. admin_get_user_detail() — pin search_path
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_get_user_detail(p_user_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  SELECT row_to_json(t) INTO profile_data
  FROM (
    SELECT
      p.id, p.email, p.sender_name, p.status, p.subscription_status,
      p.app_mode, p.last_check_in, p.timer_days, p.selected_theme,
      p.selected_soul_fire, p.warning_sent_at, p.push_66_sent_at,
      p.push_33_sent_at, p.protocol_executed_at, p.last_entry_at,
      p.had_vault_activity, p.downgrade_email_pending,
      p.created_at, p.updated_at
    FROM profiles p
    WHERE p.id = p_user_id
  ) t;

  IF profile_data IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.created_at DESC), '[]'::json) INTO entries_data
  FROM (
    SELECT
      ve.id, ve.title, ve.data_type, ve.entry_mode, ve.action_type,
      ve.status, ve.last_sent_year,
      ve.is_zero_knowledge, ve.audio_file_path,
      ve.scheduled_at, ve.grace_until, ve.sent_at, ve.created_at
    FROM vault_entries ve
    WHERE ve.user_id = p_user_id
  ) t;

  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.created_at DESC), '[]'::json) INTO devices_data
  FROM (
    SELECT pd.id, pd.platform, pd.created_at, pd.updated_at
    FROM push_devices pd
    WHERE pd.user_id = p_user_id
  ) t;

  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.expired_at DESC), '[]'::json) INTO tombs_data
  FROM (
    SELECT
      vt.vault_entry_id, vt.user_id, vt.sender_name,
      vt.sent_at, vt.expired_at, vt.created_at
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

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. admin_list_entries() — pin search_path + cap p_limit at 100
-- ═══════════════════════════════════════════════════════════════════════════

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
SET search_path = public
AS $$
DECLARE
  result      json;
  total_count bigint;
  entries_arr json;
  safe_limit  int := LEAST(GREATEST(p_limit, 1), 100);
  safe_offset int := GREATEST(p_offset, 0);
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT count(*) INTO total_count
  FROM vault_entries ve
  WHERE (
    p_status IS NULL
    OR (p_status = 'grace' AND ve.status = 'sent' AND ve.grace_until IS NOT NULL AND ve.grace_until > now())
    OR (p_status <> 'grace' AND ve.status = p_status)
  )
    AND (p_entry_mode IS NULL OR COALESCE(ve.entry_mode, 'standard') = p_entry_mode)
    AND (p_data_type IS NULL OR ve.data_type = p_data_type)
    AND (p_action_type IS NULL OR ve.action_type = p_action_type);

  SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json) INTO entries_arr
  FROM (
    SELECT
      ve.id, ve.title, ve.data_type, ve.entry_mode, ve.action_type,
      ve.status, ve.scheduled_at, ve.sent_at, ve.grace_until, ve.created_at,
      p.email AS user_email
    FROM vault_entries ve
    JOIN profiles p ON p.id = ve.user_id
    WHERE (
      p_status IS NULL
      OR (p_status = 'grace' AND ve.status = 'sent' AND ve.grace_until IS NOT NULL AND ve.grace_until > now())
      OR (p_status <> 'grace' AND ve.status = p_status)
    )
      AND (p_entry_mode IS NULL OR COALESCE(ve.entry_mode, 'standard') = p_entry_mode)
      AND (p_data_type IS NULL OR ve.data_type = p_data_type)
      AND (p_action_type IS NULL OR ve.action_type = p_action_type)
    ORDER BY ve.created_at DESC
    LIMIT safe_limit
    OFFSET safe_offset
  ) t;

  RETURN json_build_object(
    'total',   total_count,
    'entries', entries_arr
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_entries(text, text, text, text, int, int) FROM public;
REVOKE ALL ON FUNCTION public.admin_list_entries(text, text, text, text, int, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_entries(text, text, text, text, int, int) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. admin_delete_entry() — pin search_path (already safe)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_delete_entry(p_entry_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. admin_ban_user() — pin search_path + SELF-BAN PROTECTION
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_ban_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- Prevent self-ban
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'cannot ban yourself';
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

-- ═══════════════════════════════════════════════════════════════════════════
-- 9. admin_unban_user() — pin search_path (already safe)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_unban_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

-- ═══════════════════════════════════════════════════════════════════════════
-- 10. admin_delete_user() — already has search_path + self-protection
-- ═══════════════════════════════════════════════════════════════════════════

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

  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'cannot delete yourself';
  END IF;

  DELETE FROM auth.users WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_user(uuid) FROM public;
REVOKE ALL ON FUNCTION public.admin_delete_user(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_user(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 11. admin_list_heartbeat_runs() — pin search_path + cap p_limit
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_list_heartbeat_runs(
  p_limit  int DEFAULT 20,
  p_offset int DEFAULT 0
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result      json;
  total_count bigint;
  runs_arr    json;
  safe_limit  int := LEAST(GREATEST(p_limit, 1), 100);
  safe_offset int := GREATEST(p_offset, 0);
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT count(*) INTO total_count FROM heartbeat_runs;

  SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json) INTO runs_arr
  FROM (
    SELECT
      hr.id, hr.started_at, hr.completed_at, hr.runtime_seconds,
      hr.profiles_processed, hr.entries_seen,
      hr.emails_sent, hr.emails_failed,
      hr.pushes_sent, hr.pushes_failed,
      hr.entries_delivered, hr.entries_destroyed,
      hr.entries_cleaned_up, hr.bots_cleaned_up,
      hr.recurring_sent, hr.scheduled_delivered,
      hr.downgrades_processed, hr.rc_verifications,
      hr.errors, hr.warnings, hr.cleanup_stats,
      hr.resend_quota_exhausted, hr.exit_reason,
      hr.stdout_log, hr.created_at
    FROM heartbeat_runs hr
    ORDER BY hr.started_at DESC
    LIMIT safe_limit
    OFFSET safe_offset
  ) t;

  RETURN json_build_object(
    'total', total_count,
    'runs',  runs_arr
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_heartbeat_runs(int, int) FROM public;
REVOKE ALL ON FUNCTION public.admin_list_heartbeat_runs(int, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_heartbeat_runs(int, int) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 12. admin_delete_heartbeat_run() — pin search_path (already safe)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_delete_heartbeat_run(p_run_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  DELETE FROM heartbeat_runs WHERE id = p_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'heartbeat run not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_heartbeat_run(uuid) FROM public;
REVOKE ALL ON FUNCTION public.admin_delete_heartbeat_run(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_heartbeat_run(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 13. admin_clear_heartbeat_runs() — SERVER-SIDE CONFIRMATION GUARD
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_clear_heartbeat_runs(
  p_confirm text DEFAULT ''
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- Server-side double guard: must pass exact confirmation string
  IF p_confirm <> 'DELETE ALL' THEN
    RAISE EXCEPTION 'confirmation required: pass p_confirm = ''DELETE ALL''';
  END IF;

  DELETE FROM heartbeat_runs WHERE true;
  GET DIAGNOSTICS deleted_count = ROW_COUNT;

  RETURN deleted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_clear_heartbeat_runs(text) FROM public;
REVOKE ALL ON FUNCTION public.admin_clear_heartbeat_runs(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_clear_heartbeat_runs(text) TO authenticated;

-- Drop the old no-arg version if it exists
DROP FUNCTION IF EXISTS public.admin_clear_heartbeat_runs();

-- ═══════════════════════════════════════════════════════════════════════════
-- 14. admin_add_admin() — already has search_path (keeping as-is)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_add_admin(p_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  target_uid uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT id INTO target_uid
  FROM auth.users
  WHERE lower(email) = lower(trim(p_email));

  IF target_uid IS NULL THEN
    RAISE EXCEPTION 'no user found with that email';
  END IF;

  INSERT INTO admin_users (user_id, email)
  VALUES (target_uid, lower(trim(p_email)))
  ON CONFLICT (user_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_add_admin(text) FROM public;
REVOKE ALL ON FUNCTION public.admin_add_admin(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_add_admin(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 15. admin_remove_admin() — pin search_path + LAST-ADMIN GUARD
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_remove_admin(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  admin_count int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'cannot remove yourself as admin';
  END IF;

  -- Prevent removing when only 2 admins left (keep at least 1 besides yourself)
  SELECT count(*) INTO admin_count FROM admin_users;
  IF admin_count <= 1 THEN
    RAISE EXCEPTION 'cannot remove the last admin';
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

-- ═══════════════════════════════════════════════════════════════════════════
-- 16. admin_list_admins() — pin search_path
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_list_admins()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result json;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.created_at), '[]'::json) INTO result
  FROM (
    SELECT au.user_id, au.email, au.created_at
    FROM admin_users au
  ) t;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_admins() FROM public;
REVOKE ALL ON FUNCTION public.admin_list_admins() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_admins() TO authenticated;
