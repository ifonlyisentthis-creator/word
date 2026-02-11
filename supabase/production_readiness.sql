-- ============================================================================
-- PRODUCTION READINESS — Run in Supabase SQL Editor after all other SQL files.
-- Adds performance indexes, missing constraints, and scalability prep.
-- Safe to run multiple times (all statements are idempotent).
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  1. Performance indexes for vault_entries                          ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- Heartbeat script queries by user_id + status frequently
create index if not exists idx_vault_entries_user_status
  on vault_entries (user_id, status);

-- Cleanup job queries sent entries older than 30 days
create index if not exists idx_vault_entries_sent_at
  on vault_entries (sent_at)
  where status = 'sent';

-- Entry list ordered by created_at (app fetches with ORDER BY created_at DESC)
create index if not exists idx_vault_entries_user_created
  on vault_entries (user_id, created_at desc);

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  2. Performance indexes for profiles                               ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- Heartbeat script scans profiles by status + last_check_in for expired users
create index if not exists idx_profiles_active_checkin
  on profiles (last_check_in)
  where status = 'active';

-- Heartbeat push notification passes query by push_66/33_sent_at IS NULL
create index if not exists idx_profiles_push_pending
  on profiles (last_check_in)
  where status = 'active'
    and push_66_sent_at is null;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  3. Performance indexes for push_devices                           ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- FCM token lookup by user
create index if not exists idx_push_devices_user
  on push_devices (user_id);

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  4. Ensure NOT NULL constraints on critical columns                ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- These are safe even if already set (Postgres ignores if already NOT NULL)
do $$
begin
  -- vault_entries.user_id must never be null
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'vault_entries'
      and column_name = 'user_id'
      and is_nullable = 'YES'
  ) then
    alter table vault_entries alter column user_id set not null;
  end if;

  -- vault_entries.status must never be null
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'vault_entries'
      and column_name = 'status'
      and is_nullable = 'YES'
  ) then
    alter table vault_entries alter column status set not null;
  end if;

  -- vault_entries.action_type must never be null
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'vault_entries'
      and column_name = 'action_type'
      and is_nullable = 'YES'
  ) then
    alter table vault_entries alter column action_type set not null;
  end if;

  -- profiles.status must never be null (default 'active')
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'status'
      and is_nullable = 'YES'
  ) then
    alter table profiles alter column status set default 'active';
    alter table profiles alter column status set not null;
  end if;

  -- profiles.subscription_status must never be null (default 'free')
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'subscription_status'
      and is_nullable = 'YES'
  ) then
    alter table profiles alter column subscription_status set default 'free';
    alter table profiles alter column subscription_status set not null;
  end if;

  -- profiles.timer_days must never be null (default 30)
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'timer_days'
      and is_nullable = 'YES'
  ) then
    alter table profiles alter column timer_days set default 30;
    alter table profiles alter column timer_days set not null;
  end if;
end $$;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  5. CHECK constraints for valid enum values                        ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- profiles.status
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_status_check' and conrelid = 'profiles'::regclass
  ) then
    alter table profiles add constraint profiles_status_check
      check (status in ('active', 'inactive', 'archived'));
  end if;
end $$;

-- profiles.subscription_status
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_sub_status_check' and conrelid = 'profiles'::regclass
  ) then
    alter table profiles add constraint profiles_sub_status_check
      check (subscription_status in ('free', 'pro', 'lifetime'));
  end if;
end $$;

-- vault_entries.status
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'vault_entries_status_check' and conrelid = 'vault_entries'::regclass
  ) then
    alter table vault_entries add constraint vault_entries_status_check
      check (status in ('active', 'sending', 'sent'));
  end if;
end $$;

-- vault_entries.action_type
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'vault_entries_action_check' and conrelid = 'vault_entries'::regclass
  ) then
    alter table vault_entries add constraint vault_entries_action_check
      check (action_type in ('send', 'destroy'));
  end if;
end $$;

-- vault_entries.data_type
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'vault_entries_data_type_check' and conrelid = 'vault_entries'::regclass
  ) then
    alter table vault_entries add constraint vault_entries_data_type_check
      check (data_type in ('text', 'audio'));
  end if;
end $$;

-- profiles.timer_days range
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_timer_days_range' and conrelid = 'profiles'::regclass
  ) then
    alter table profiles add constraint profiles_timer_days_range
      check (timer_days >= 7 and timer_days <= 3650);
  end if;
end $$;

-- vault_entries.audio_duration_seconds cap (600s = 10 min bank)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'vault_entries_audio_duration_cap' and conrelid = 'vault_entries'::regclass
  ) then
    alter table vault_entries add constraint vault_entries_audio_duration_cap
      check (audio_duration_seconds is null or audio_duration_seconds <= 600);
  end if;
end $$;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  6. Verify RLS policies exist for profiles (own-row access)        ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- SELECT own profile
do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'profiles' and policyname = 'Users can view own profile'
  ) then
    create policy "Users can view own profile"
      on profiles for select
      using (auth.uid() = id);
  end if;
end $$;

-- INSERT own profile (sign-up)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'profiles' and policyname = 'Users can insert own profile'
  ) then
    create policy "Users can insert own profile"
      on profiles for insert
      with check (auth.uid() = id);
  end if;
end $$;

-- UPDATE own profile (only hmac_key_encrypted via column grant)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'profiles' and policyname = 'Users can update own profile'
  ) then
    create policy "Users can update own profile"
      on profiles for update
      using (auth.uid() = id);
  end if;
end $$;

-- DELETE own profile (explicit account deletion)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'profiles' and policyname = 'Users can delete own profile'
  ) then
    create policy "Users can delete own profile"
      on profiles for delete
      using (auth.uid() = id);
  end if;
end $$;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  7. Verify RLS policies exist for vault_entries                    ║
-- ╚══════════════════════════════════════════════════════════════════════╝

do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'vault_entries' and policyname = 'Users can view own entries'
  ) then
    create policy "Users can view own entries"
      on vault_entries for select
      using (auth.uid() = user_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'vault_entries' and policyname = 'Users can insert own entries'
  ) then
    create policy "Users can insert own entries"
      on vault_entries for insert
      with check (auth.uid() = user_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'vault_entries' and policyname = 'Users can update own entries'
  ) then
    create policy "Users can update own entries"
      on vault_entries for update
      using (auth.uid() = user_id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'vault_entries' and policyname = 'Users can delete own entries'
  ) then
    create policy "Users can delete own entries"
      on vault_entries for delete
      using (auth.uid() = user_id);
  end if;
end $$;

-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  8. Diagnostic queries (run manually to verify)                    ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- Check all indexes:
-- SELECT indexname, tablename FROM pg_indexes WHERE schemaname = 'public' ORDER BY tablename;

-- Check all constraints:
-- SELECT conname, conrelid::regclass, contype FROM pg_constraint WHERE connamespace = 'public'::regnamespace ORDER BY conrelid::regclass::text;

-- Check all RLS policies:
-- SELECT tablename, policyname, permissive, cmd FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename;

-- Check all triggers:
-- SELECT tgname, tgrelid::regclass FROM pg_trigger WHERE tgrelid::regclass::text IN ('profiles', 'vault_entries', 'push_devices') AND NOT tgisinternal ORDER BY tgrelid::regclass::text;
