-- DROP the vulnerable sync_my_subscription_status RPC.
drop function if exists public.sync_my_subscription_status(text);

-- edge_set_subscription_status: called ONLY by the verify-subscription Edge Function.
-- 
-- The Edge Function already verified the purchase with RevenueCat's server-side API,
-- so this function just needs to perform the DB update.
--
-- SECURITY DEFINER + GUC override is needed because the guard_subscription_status
-- trigger checks request.jwt.claim.role = 'service_role'. Even though the Edge
-- Function uses the service_role key, the GUC isn't always set correctly when
-- calling via the Supabase JS client from within Edge Functions.
--
-- This function is restricted to service_role only — no client can call it.
--
-- Run this in the Supabase SQL Editor (Dashboard → SQL Editor → New Query).

create or replace function public.edge_set_subscription_status(
  target_user_id uuid,
  new_status text
)
returns void
language plpgsql
security definer
as $$
declare
  old_role text;
begin
  if new_status not in ('free', 'pro', 'lifetime') then
    raise exception 'invalid subscription status: %', new_status;
  end if;

  -- Temporarily override the GUC so guard_subscription_status trigger passes.
  old_role := coalesce(current_setting('request.jwt.claim.role', true), '');
  perform set_config('request.jwt.claim.role', 'service_role', true);

  update profiles
  set subscription_status = new_status
  where id = target_user_id;

  -- Restore original role.
  perform set_config('request.jwt.claim.role', old_role, true);
end;
$$;

-- Only service_role can call this. Clients cannot.
revoke all on function public.edge_set_subscription_status(uuid, text) from anon, authenticated;
grant execute on function public.edge_set_subscription_status(uuid, text) to service_role;
