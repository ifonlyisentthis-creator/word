create or replace function public.update_check_in(user_id uuid, timer_days int default null)
returns profiles
language plpgsql
security definer
as $$
declare
  result profiles;
  sub text;
  effective_timer int;
  max_timer int;
begin
  if auth.uid() <> user_id then
    raise exception 'not authorized';
  end if;

  select subscription_status, timer_days
  into sub, effective_timer
  from profiles
  where id = user_id;

  if sub is null then
    raise exception 'profile not found';
  end if;

  if sub = 'lifetime' then
    max_timer := 3650;
  elsif sub = 'pro' then
    max_timer := 365;
  else
    max_timer := 30;
  end if;

  if sub not in ('pro','lifetime') then
    effective_timer := 30;
  elsif timer_days is not null then
    effective_timer := greatest(7, least(max_timer, timer_days));
  end if;

  update profiles
  set last_check_in = now(),
      timer_days = effective_timer,
      warning_sent_at = null
  where id = user_id
  returning * into result;

  return result;
end;
$$;

create or replace function public.guard_timer_days()
returns trigger
language plpgsql
as $$
declare
  max_timer int;
begin
  if new.timer_days is distinct from old.timer_days then
    if auth.role() <> 'service_role' then
      if old.subscription_status = 'lifetime' then
        max_timer := 3650;
        new.timer_days := greatest(7, least(max_timer, new.timer_days));
      elsif old.subscription_status = 'pro' then
        max_timer := 365;
        new.timer_days := greatest(7, least(max_timer, new.timer_days));
      else
        new.timer_days := 30;
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_guard_timer_days on profiles;
create trigger profiles_guard_timer_days
before update on profiles
for each row
execute function public.guard_timer_days();
