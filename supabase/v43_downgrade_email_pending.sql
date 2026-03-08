-- v43: Add downgrade_email_pending flag for reliable downgrade email delivery.
--
-- Root cause: handle_subscription_downgrade wiped premium indicators (timer,
-- themes, audio) BEFORE attempting the email send. If the email failed due to
-- a transient error (rate limit, network timeout), the next heartbeat run
-- could no longer detect that a downgrade had occurred — the email was
-- permanently lost.
--
-- Fix: A boolean flag tracks whether the downgrade notification email still
-- needs to be sent. The heartbeat sets it to TRUE during the indicator wipe
-- and only clears it after the email is successfully delivered. On subsequent
-- runs, if the flag is still TRUE, the heartbeat retries the email.
--
-- The edge_set_subscription_status RPC is updated to clear the flag whenever
-- the user re-subscribes (status goes to pro/lifetime), so a future downgrade
-- will trigger a fresh notification.

-- 1. Add the column
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS downgrade_email_pending boolean DEFAULT false;

-- 2. Update edge_set_subscription_status to clear flag on re-subscribe
CREATE OR REPLACE FUNCTION public.edge_set_subscription_status(
  target_user_id uuid, new_status text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE old_role text;
BEGIN
  IF new_status NOT IN ('free', 'pro', 'lifetime') THEN
    RAISE EXCEPTION 'invalid subscription status: %', new_status;
  END IF;
  old_role := COALESCE(current_setting('request.jwt.claim.role', true), '');
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  UPDATE profiles
    SET subscription_status = new_status,
        downgrade_email_pending = CASE
          WHEN new_status IN ('pro', 'lifetime') THEN false
          ELSE downgrade_email_pending
        END
    WHERE id = target_user_id;
  PERFORM set_config('request.jwt.claim.role', old_role, true);
END;
$$;

REVOKE ALL ON FUNCTION public.edge_set_subscription_status(uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.edge_set_subscription_status(uuid, text) TO service_role;
