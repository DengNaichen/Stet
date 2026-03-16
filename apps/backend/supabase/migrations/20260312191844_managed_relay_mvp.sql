create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table if not exists public.user_entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  managed_enabled boolean not null default true,
  requests_per_minute integer not null default 10 check (requests_per_minute > 0),
  daily_audio_seconds integer not null default 1800 check (daily_audio_seconds >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.usage_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  user_id uuid not null references auth.users (id) on delete cascade,
  route_kind text not null check (route_kind in ('responses', 'audio_transcriptions')),
  request_units integer not null default 1 check (request_units > 0),
  audio_seconds integer not null default 0 check (audio_seconds >= 0),
  provider text not null check (provider in ('openai')),
  upstream_status integer,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists usage_events_user_created_at_idx
  on public.usage_events (user_id, created_at desc);

drop trigger if exists set_user_entitlements_updated_at on public.user_entitlements;

create trigger set_user_entitlements_updated_at
before update on public.user_entitlements
for each row
execute function public.set_updated_at();

alter table public.user_entitlements enable row level security;
alter table public.usage_events enable row level security;

create or replace function public.check_and_record_managed_usage(
  p_user_id uuid,
  p_request_id uuid,
  p_route_kind text,
  p_request_units integer default 1,
  p_audio_seconds integer default 0,
  p_provider text default 'openai'
)
returns table (
  allowed boolean,
  reason text,
  retry_after_seconds integer,
  request_id uuid,
  usage_event_id uuid,
  requests_remaining integer,
  daily_audio_seconds_remaining integer,
  requests_used_last_minute integer,
  audio_seconds_used_last_day integer
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_entitlement public.user_entitlements%rowtype;
  v_requests_used_last_minute integer := 0;
  v_audio_seconds_used_last_day integer := 0;
  v_request_retry_after_seconds integer := null;
  v_audio_retry_after_seconds integer := null;
  v_usage_event_id uuid := null;
begin
  insert into public.user_entitlements (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select *
  into v_entitlement
  from public.user_entitlements
  where user_id = p_user_id
  for update;

  select
    coalesce(sum(request_units), 0),
    coalesce(
      ceil(extract(epoch from min(created_at + interval '1 minute' - timezone('utc', now()))))::integer,
      0
    )
  into
    v_requests_used_last_minute,
    v_request_retry_after_seconds
  from public.usage_events
  where user_id = p_user_id
    and created_at >= timezone('utc', now()) - interval '1 minute';

  select
    coalesce(sum(audio_seconds), 0),
    coalesce(
      ceil(extract(epoch from min(created_at + interval '1 day' - timezone('utc', now()))))::integer,
      0
    )
  into
    v_audio_seconds_used_last_day,
    v_audio_retry_after_seconds
  from public.usage_events
  where user_id = p_user_id
    and created_at >= timezone('utc', now()) - interval '1 day'
    and route_kind = 'audio_transcriptions';

  if v_requests_used_last_minute + p_request_units > v_entitlement.requests_per_minute then
    return query
    select
      false,
      'request_limit_exceeded',
      greatest(coalesce(v_request_retry_after_seconds, 1), 1),
      p_request_id,
      null::uuid,
      greatest(v_entitlement.requests_per_minute - v_requests_used_last_minute, 0),
      greatest(v_entitlement.daily_audio_seconds - v_audio_seconds_used_last_day, 0),
      v_requests_used_last_minute,
      v_audio_seconds_used_last_day;
    return;
  end if;

  if p_route_kind = 'audio_transcriptions'
     and v_audio_seconds_used_last_day + p_audio_seconds > v_entitlement.daily_audio_seconds then
    return query
    select
      false,
      'audio_limit_exceeded',
      greatest(coalesce(v_audio_retry_after_seconds, 1), 1),
      p_request_id,
      null::uuid,
      greatest(v_entitlement.requests_per_minute - v_requests_used_last_minute, 0),
      greatest(v_entitlement.daily_audio_seconds - v_audio_seconds_used_last_day, 0),
      v_requests_used_last_minute,
      v_audio_seconds_used_last_day;
    return;
  end if;

  insert into public.usage_events (
    request_id,
    user_id,
    route_kind,
    request_units,
    audio_seconds,
    provider
  )
  values (
    p_request_id,
    p_user_id,
    p_route_kind,
    p_request_units,
    p_audio_seconds,
    p_provider
  )
  returning id into v_usage_event_id;

  return query
  select
    true,
    null::text,
    null::integer,
    p_request_id,
    v_usage_event_id,
    greatest(v_entitlement.requests_per_minute - (v_requests_used_last_minute + p_request_units), 0),
    greatest(v_entitlement.daily_audio_seconds - (v_audio_seconds_used_last_day + p_audio_seconds), 0),
    v_requests_used_last_minute + p_request_units,
    v_audio_seconds_used_last_day + p_audio_seconds;
end;
$$;

create or replace function public.get_managed_usage_summary(p_user_id uuid)
returns table (
  requests_used_last_minute integer,
  audio_seconds_used_last_day integer
)
language sql
security definer
set search_path = public, auth
as $$
  select
    coalesce((
      select sum(request_units)::integer
      from public.usage_events
      where user_id = p_user_id
        and created_at >= timezone('utc', now()) - interval '1 minute'
    ), 0) as requests_used_last_minute,
    coalesce((
      select sum(audio_seconds)::integer
      from public.usage_events
      where user_id = p_user_id
        and route_kind = 'audio_transcriptions'
        and created_at >= timezone('utc', now()) - interval '1 day'
    ), 0) as audio_seconds_used_last_day;
$$;
