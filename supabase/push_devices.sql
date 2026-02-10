create table if not exists public.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  fcm_token text not null unique,
  platform text not null,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.push_devices enable row level security;

create policy "push_devices_select_own" on public.push_devices
for select
to authenticated
using (auth.uid() = user_id);

create policy "push_devices_insert_own" on public.push_devices
for insert
to authenticated
with check (auth.uid() = user_id);

create policy "push_devices_update_own" on public.push_devices
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "push_devices_delete_own" on public.push_devices
for delete
to authenticated
using (auth.uid() = user_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_push_devices_updated_at on public.push_devices;
create trigger set_push_devices_updated_at
before update on public.push_devices
for each row
execute function public.set_updated_at();
