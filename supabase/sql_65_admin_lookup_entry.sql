-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  sql_65 — admin_lookup_entry: reverse-lookup entry by ID              ║
-- ║  Returns entry details + sender profile for report handling.          ║
-- ║  Safe to re-run (CREATE OR REPLACE).                                  ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.admin_lookup_entry(p_entry_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  entry_data json;
  sender_data json;
  v_user_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- Get entry (any status — sent, active, grace, etc.)
  SELECT row_to_json(t), t.user_id INTO entry_data, v_user_id
  FROM (
    SELECT
      ve.id, ve.user_id, ve.title, ve.data_type, ve.entry_mode,
      ve.action_type, ve.status, ve.scheduled_at, ve.sent_at,
      ve.grace_until, ve.created_at
    FROM vault_entries ve
    WHERE ve.id = p_entry_id
  ) t;

  IF entry_data IS NULL THEN
    RETURN NULL;
  END IF;

  -- Get sender profile
  SELECT row_to_json(t) INTO sender_data
  FROM (
    SELECT p.id, p.email, p.sender_name, p.status, p.subscription_status
    FROM profiles p
    WHERE p.id = v_user_id
  ) t;

  RETURN json_build_object(
    'entry',  entry_data,
    'sender', sender_data
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_lookup_entry(uuid) FROM public;
REVOKE ALL ON FUNCTION public.admin_lookup_entry(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_lookup_entry(uuid) TO authenticated;
