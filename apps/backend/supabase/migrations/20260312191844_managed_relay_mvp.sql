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
  weekly_transcription_chars integer not null default 50000 check (weekly_transcription_chars >= 0),
  min_billed_chars_per_transcription integer not null default 100 check (min_billed_chars_per_transcription > 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.usage_events (
  id uuid primary key default gen_random_uuid(),
  request_id text not null unique check (char_length(request_id) between 1 and 128),
  user_id uuid not null references auth.users (id) on delete cascade,
  route_kind text not null check (route_kind in ('audio_transcriptions')),
  request_units integer not null default 1 check (request_units > 0),
  transcription_chars integer not null default 0 check (transcription_chars >= 0),
  billed_chars integer not null default 0 check (billed_chars >= 0),
  provider text not null check (provider in ('openai', 'groq')),
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

create or replace function public.begin_managed_transcription_usage(
  p_user_id uuid,
  p_request_id text,
  p_provider text default 'openai'
)
returns table (
  allowed boolean,
  reason text,
  retry_after_seconds integer,
  request_id text,
  usage_event_id uuid,
  requests_remaining integer,
  weekly_transcription_chars_remaining integer,
  requests_used_last_minute integer,
  transcription_chars_used_last_week integer,
  reserved_billed_chars integer
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_entitlement public.user_entitlements%rowtype;
  v_requests_used_last_minute integer := 0;
  v_transcription_chars_used_last_week integer := 0;
  v_request_retry_after_seconds integer := null;
  v_quota_retry_after_seconds integer := null;
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
    coalesce(sum(billed_chars), 0)
  into
    v_transcription_chars_used_last_week
  from public.usage_events
  where user_id = p_user_id
    and route_kind = 'audio_transcriptions'
    and created_at >= timezone('utc', now()) - interval '7 days';

  select
    coalesce(
      ceil(extract(epoch from min(created_at + interval '7 days' - timezone('utc', now()))))::integer,
      0
    )
  into
    v_quota_retry_after_seconds
  from public.usage_events
  where user_id = p_user_id
    and route_kind = 'audio_transcriptions'
    and billed_chars > 0
    and created_at >= timezone('utc', now()) - interval '7 days';

  if v_requests_used_last_minute + 1 > v_entitlement.requests_per_minute then
    return query
    select
      false,
      'request_limit_exceeded',
      greatest(coalesce(v_request_retry_after_seconds, 1), 1),
      p_request_id,
      null::uuid,
      greatest(v_entitlement.requests_per_minute - v_requests_used_last_minute, 0),
      greatest(v_entitlement.weekly_transcription_chars - v_transcription_chars_used_last_week, 0),
      v_requests_used_last_minute,
      v_transcription_chars_used_last_week,
      0;
    return;
  end if;

  if v_transcription_chars_used_last_week + v_entitlement.min_billed_chars_per_transcription
     > v_entitlement.weekly_transcription_chars then
    return query
    select
      false,
      'transcription_chars_limit_exceeded',
      greatest(coalesce(v_quota_retry_after_seconds, 1), 1),
      p_request_id,
      null::uuid,
      greatest(v_entitlement.requests_per_minute - v_requests_used_last_minute, 0),
      greatest(v_entitlement.weekly_transcription_chars - v_transcription_chars_used_last_week, 0),
      v_requests_used_last_minute,
      v_transcription_chars_used_last_week,
      0;
    return;
  end if;

  insert into public.usage_events (
    request_id,
    user_id,
    route_kind,
    request_units,
    transcription_chars,
    billed_chars,
    provider
  )
  values (
    p_request_id,
    p_user_id,
    'audio_transcriptions',
    1,
    0,
    v_entitlement.min_billed_chars_per_transcription,
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
    greatest(v_entitlement.requests_per_minute - (v_requests_used_last_minute + 1), 0),
    greatest(
      v_entitlement.weekly_transcription_chars
        - (v_transcription_chars_used_last_week + v_entitlement.min_billed_chars_per_transcription),
      0
    ),
    v_requests_used_last_minute + 1,
    v_transcription_chars_used_last_week + v_entitlement.min_billed_chars_per_transcription,
    v_entitlement.min_billed_chars_per_transcription;
end;
$$;

create or replace function public.finalize_managed_transcription_usage(
  p_usage_event_id uuid,
  p_transcription_chars integer,
  p_billed_chars integer,
  p_upstream_status integer
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  update public.usage_events
  set
    transcription_chars = greatest(p_transcription_chars, 0),
    billed_chars = greatest(p_billed_chars, 0),
    upstream_status = p_upstream_status
  where id = p_usage_event_id;

  if not found then
    raise exception 'usage_event_not_found'
      using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.get_managed_usage_summary(p_user_id uuid)
returns table (
  requests_used_last_minute integer,
  transcription_chars_used_last_week integer
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
      select sum(billed_chars)::integer
      from public.usage_events
      where user_id = p_user_id
        and route_kind = 'audio_transcriptions'
        and created_at >= timezone('utc', now()) - interval '7 days'
    ), 0) as transcription_chars_used_last_week;
$$;
