-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  sql_62 — Add stdout_log column to heartbeat_runs                      ║
-- ║  Captures full print() output from each heartbeat run.                 ║
-- ║  Safe to re-run (idempotent).                                          ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- 1. Add column (no-op if already exists)
ALTER TABLE heartbeat_runs ADD COLUMN IF NOT EXISTS stdout_log text DEFAULT '';

-- 2. Update admin_list_heartbeat_runs to include stdout_log
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
      hr.stdout_log,
      hr.created_at
    FROM heartbeat_runs hr
    ORDER BY hr.started_at DESC
    LIMIT p_limit
    OFFSET p_offset
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

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  3. admin_delete_heartbeat_run() — delete a single run                 ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_delete_heartbeat_run(p_run_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  4. admin_clear_heartbeat_runs() — delete ALL runs                     ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_clear_heartbeat_runs()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  DELETE FROM heartbeat_runs;
  GET DIAGNOSTICS deleted_count = ROW_COUNT;

  RETURN deleted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_clear_heartbeat_runs() FROM public;
REVOKE ALL ON FUNCTION public.admin_clear_heartbeat_runs() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_clear_heartbeat_runs() TO authenticated;
