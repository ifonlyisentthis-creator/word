-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  sql_64 — Real ban system                                              ║
-- ║  Banning = delete all user data + block the email from re-registering. ║
-- ║  Safe to re-run (idempotent).                                          ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═════════════════════════════════════════════════════════════════════════════
-- 1. banned_emails table
-- ═════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.banned_emails (
  email      text        PRIMARY KEY,
  banned_at  timestamptz NOT NULL DEFAULT now(),
  banned_by  uuid        REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Lock down direct access — only admin RPCs touch this table.
ALTER TABLE public.banned_emails ENABLE ROW LEVEL SECURITY;
-- No RLS policies = no direct access from any role (anon, authenticated).
-- SECURITY DEFINER RPCs bypass RLS.

-- ═════════════════════════════════════════════════════════════════════════════
-- 2. Trigger: block banned emails from creating profiles
--    When a banned user re-signs in via Google, auth.users row gets recreated.
--    This trigger fires BEFORE INSERT on profiles and rejects the row, which
--    causes the Flutter app to detect the error and sign out.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.check_banned_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM banned_emails WHERE email = NEW.email) THEN
    -- Custom error code P0403 — detected by the Flutter app to show ban message.
    -- Note: the auth.users row created by Google sign-in survives as an orphan,
    -- but without a profile the user can do nothing.  The next sign-in attempt
    -- reuses the same auth row (same email = same uid in GoTrue), so orphans
    -- don't pile up.
    RAISE EXCEPTION 'account_banned'
      USING ERRCODE = 'P0403',
            HINT    = 'This account has been suspended.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_banned_email ON profiles;
CREATE TRIGGER trg_check_banned_email
  BEFORE INSERT ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.check_banned_email();

-- ═════════════════════════════════════════════════════════════════════════════
-- 2b. Patch handle_new_user() so it silently skips banned emails.
--     Without this, the AFTER INSERT trigger on auth.users would try to INSERT
--     a profile, hit trg_check_banned_email, and raise P0403 — which causes
--     GoTrue to return a 500 on sign-in instead of letting the Flutter app
--     show our clean ban screen.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- If the email is banned, do NOT create a profile.
  -- The Flutter app will attempt ensureProfile() → trg_check_banned_email
  -- fires → P0403 → clean ban screen → sign out.
  IF EXISTS (SELECT 1 FROM banned_emails WHERE email = NEW.email) THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.profiles (id, email, sender_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NULLIF(TRIM(COALESCE(NEW.raw_user_meta_data->>'name','')), ''), 'Afterword')
  )
  ON CONFLICT (id) DO UPDATE SET email = excluded.email;

  RETURN NEW;
END;
$$;

-- ═════════════════════════════════════════════════════════════════════════════
-- 3. Replace admin_ban_user() — now does a REAL ban:
--    capture email → insert into banned_emails → delete from auth.users
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_ban_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_email text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  -- Prevent self-ban
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'cannot ban yourself';
  END IF;

  -- Get email before we delete everything
  SELECT email INTO v_email FROM profiles WHERE id = p_user_id;
  IF v_email IS NULL THEN
    -- Fallback: try auth.users
    SELECT email INTO v_email FROM auth.users WHERE id = p_user_id;
  END IF;

  IF v_email IS NULL THEN
    RAISE EXCEPTION 'user not found';
  END IF;

  -- Add to ban list (skip if already there)
  INSERT INTO banned_emails (email, banned_by)
  VALUES (v_email, auth.uid())
  ON CONFLICT (email) DO NOTHING;

  -- Delete from auth.users — CASCADE removes profiles, vault_entries,
  -- devices, sessions, refresh_tokens, etc.
  DELETE FROM auth.users WHERE id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_ban_user(uuid) FROM public;
REVOKE ALL ON FUNCTION public.admin_ban_user(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_ban_user(uuid) TO authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- 4. Replace admin_unban_user() — now takes EMAIL, removes from ban list.
--    The old version took p_user_id (uuid) — we drop that overload.
-- ═════════════════════════════════════════════════════════════════════════════

-- Drop old uuid-based overload
DROP FUNCTION IF EXISTS public.admin_unban_user(uuid);

CREATE OR REPLACE FUNCTION public.admin_unban_user(p_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  DELETE FROM banned_emails WHERE email = p_email;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'email not in ban list';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_unban_user(text) FROM public;
REVOKE ALL ON FUNCTION public.admin_unban_user(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_unban_user(text) TO authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- 5. admin_list_banned() — list all banned emails
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_list_banned()
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

  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.banned_at DESC), '[]'::json)
  INTO result
  FROM (
    SELECT email, banned_at
    FROM banned_emails
    ORDER BY banned_at DESC
  ) t;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_banned() FROM public;
REVOKE ALL ON FUNCTION public.admin_list_banned() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_banned() TO authenticated;
