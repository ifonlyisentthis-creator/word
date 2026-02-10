-- ============================================================================
-- SECURITY HARDENING — Run in Supabase SQL Editor
-- Belt-and-suspenders checks to ensure no modded app can access pro features.
-- Safe to run multiple times (all statements are idempotent).
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  1. DROP any leftover vulnerable functions                         ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- The old sync_my_subscription_status let any authenticated user set their
-- own subscription_status to 'lifetime'. It must be gone.
drop function if exists public.sync_my_subscription_status(text);

-- The original block_subscription_status_changes (SQL.txt #2) was replaced
-- by guard_subscription_status. Drop the old trigger function if lingering.
drop function if exists public.block_subscription_status_changes() cascade;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  2. Ensure EXECUTE grants are locked down                          ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- set_subscription_status: service_role ONLY (used by webhook / heartbeat)
revoke all on function public.set_subscription_status(uuid, text) from anon, authenticated;
grant execute on function public.set_subscription_status(uuid, text) to service_role;

-- edge_set_subscription_status: service_role ONLY (used by verify-subscription Edge Function)
revoke all on function public.edge_set_subscription_status(uuid, text) from anon, authenticated;
grant execute on function public.edge_set_subscription_status(uuid, text) to service_role;

-- cleanup_sent_entries: no client access needed (cron / heartbeat only)
revoke all on function public.cleanup_sent_entries() from anon, authenticated;
grant execute on function public.cleanup_sent_entries() to service_role;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  3. Column-level grants (ensure push columns are included)         ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- Revoke broad UPDATE from client roles
revoke update on profiles from authenticated, anon;

-- Authenticated users can only directly UPDATE hmac_key_encrypted
-- (all other mutations go through SECURITY DEFINER RPCs)
grant update (hmac_key_encrypted) on profiles to authenticated;

-- Service role can update server-managed columns
grant update (subscription_status, status, warning_sent_at, push_66_sent_at, push_33_sent_at) on profiles to service_role;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  4. Verify guard triggers exist                                    ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- Re-create guard_subscription_status trigger (idempotent)
drop trigger if exists protect_subscription_status on profiles;
create trigger protect_subscription_status
before update on profiles
for each row execute function guard_subscription_status();

-- Re-create guard_timer_days trigger (idempotent)
drop trigger if exists profiles_guard_timer_days on profiles;
create trigger profiles_guard_timer_days
before update on profiles
for each row execute function guard_timer_days();

-- Re-create audio time bank trigger (idempotent)
drop trigger if exists vault_entries_audio_bank on vault_entries;
create trigger vault_entries_audio_bank
before insert or update on vault_entries
for each row execute function enforce_audio_time_bank();

-- Re-create rate limit trigger (idempotent)
drop trigger if exists vault_entries_rate_limit on vault_entries;
create trigger vault_entries_rate_limit
before insert on vault_entries
for each row execute function enforce_entry_rate_limit();

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  5. Ensure RLS is ON for all tables                                ║
-- ╚══════════════════════════════════════════════════════════════════════╝

alter table profiles enable row level security;
alter table vault_entries enable row level security;
alter table push_devices enable row level security;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  6. Diagnostic: list all public functions callable by authenticated ║
-- ║     (Run this SELECT separately to review — should show only       ║
-- ║     update_check_in, update_sender_name, viewer_entry_status)      ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- Uncomment to audit:
-- SELECT p.proname, r.rolname
-- FROM pg_proc p
-- JOIN pg_namespace n ON p.pronamespace = n.oid
-- JOIN pg_roles r ON has_function_privilege(r.oid, p.oid, 'EXECUTE')
-- WHERE n.nspname = 'public'
--   AND r.rolname IN ('authenticated', 'anon')
-- ORDER BY p.proname, r.rolname;
