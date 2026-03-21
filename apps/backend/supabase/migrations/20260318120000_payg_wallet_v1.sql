create extension if not exists pgcrypto;

create table if not exists public.billing_accounts (
  user_id uuid primary key references auth.users (id) on delete cascade,
  balance_credits integer not null default 0 check (balance_credits >= 0),
  currency text not null default 'usd',
  managed_enabled boolean not null default true,
  auto_recharge_enabled boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.billing_pricing_rules (
  id uuid primary key default gen_random_uuid(),
  usage_kind text not null check (usage_kind in ('asr', 'rewrite')),
  provider text not null check (provider in ('openai', 'groq')),
  unit_name text not null check (unit_name in ('second', 'char')),
  unit_size numeric not null default 1 check (unit_size > 0),
  credits_per_unit integer not null default 1 check (credits_per_unit > 0),
  minimum_credits integer not null default 1 check (minimum_credits >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (usage_kind, provider)
);

create table if not exists public.credit_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references public.billing_accounts (user_id) on delete cascade,
  ledger_kind text not null check (ledger_kind in ('topup', 'usage', 'refund', 'adjustment')),
  usage_kind text check (usage_kind in ('asr', 'rewrite')),
  request_id text,
  external_reference text,
  credit_delta integer not null,
  balance_after integer not null check (balance_after >= 0),
  quantity numeric not null default 0,
  provider text check (provider in ('openai', 'groq', 'stripe')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists credit_ledger_external_reference_idx
  on public.credit_ledger (external_reference)
  where external_reference is not null;

create index if not exists credit_ledger_user_created_at_idx
  on public.credit_ledger (user_id, created_at desc);

alter table public.billing_accounts enable row level security;
alter table public.billing_pricing_rules enable row level security;
alter table public.credit_ledger enable row level security;

drop trigger if exists set_billing_accounts_updated_at on public.billing_accounts;
create trigger set_billing_accounts_updated_at
before update on public.billing_accounts
for each row
execute function public.set_updated_at();

drop trigger if exists set_billing_pricing_rules_updated_at on public.billing_pricing_rules;
create trigger set_billing_pricing_rules_updated_at
before update on public.billing_pricing_rules
for each row
execute function public.set_updated_at();

alter table public.usage_events
  add column if not exists usage_kind text check (usage_kind in ('asr', 'rewrite'));

alter table public.usage_events
  add column if not exists billable_quantity numeric not null default 0;

alter table public.usage_events
  add column if not exists reserved_credits integer not null default 0;

alter table public.usage_events
  add column if not exists billed_credits integer not null default 0;

alter table public.usage_events
  add column if not exists status text not null default 'reserved' check (status in ('reserved', 'completed', 'refunded'));

alter table public.usage_events
  add column if not exists billing_account_id uuid references public.billing_accounts (user_id) on delete cascade;

alter table public.usage_events
  add column if not exists credit_ledger_id uuid references public.credit_ledger (id) on delete set null;

alter table public.usage_events
  add column if not exists finalized_at timestamptz;

alter table public.usage_events
  add column if not exists refunded_at timestamptz;

alter table public.usage_events
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create index if not exists usage_events_user_created_at_idx
  on public.usage_events (user_id, created_at desc);

insert into public.billing_pricing_rules (
  usage_kind,
  provider,
  unit_name,
  unit_size,
  credits_per_unit,
  minimum_credits,
  is_active
)
values
  ('asr', 'openai', 'second', 1, 1, 1, true),
  ('asr', 'groq', 'second', 1, 1, 1, true),
  ('rewrite', 'openai', 'char', 100, 1, 1, true),
  ('rewrite', 'groq', 'char', 100, 1, 1, true)
on conflict (usage_kind, provider) do update
set
  unit_name = excluded.unit_name,
  unit_size = excluded.unit_size,
  credits_per_unit = excluded.credits_per_unit,
  minimum_credits = excluded.minimum_credits,
  is_active = excluded.is_active;

create or replace function public.ensure_billing_account(p_user_id uuid)
returns public.billing_accounts
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_account public.billing_accounts%rowtype;
begin
  insert into public.billing_accounts (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select *
  into v_account
  from public.billing_accounts
  where user_id = p_user_id
  for update;

  return v_account;
end;
$$;

create or replace function public.get_managed_wallet_summary(p_user_id uuid)
returns table (
  balance_credits integer,
  recent_usage_credits_7d integer,
  recent_topup_credits_7d integer,
  total_usage_credits integer,
  total_topup_credits integer
)
language sql
security definer
set search_path = public, auth
as $$
  select
    coalesce((
      select balance_credits
      from public.billing_accounts
      where user_id = p_user_id
    ), 0) as balance_credits,
    coalesce((
      select sum(greatest(-credit_delta, 0))::integer
      from public.credit_ledger
      where user_id = p_user_id
        and ledger_kind = 'usage'
        and created_at >= timezone('utc', now()) - interval '7 days'
    ), 0) as recent_usage_credits_7d,
    coalesce((
      select sum(greatest(credit_delta, 0))::integer
      from public.credit_ledger
      where user_id = p_user_id
        and ledger_kind = 'topup'
        and created_at >= timezone('utc', now()) - interval '7 days'
    ), 0) as recent_topup_credits_7d,
    coalesce((
      select sum(greatest(-credit_delta, 0))::integer
      from public.credit_ledger
      where user_id = p_user_id
        and ledger_kind = 'usage'
    ), 0) as total_usage_credits,
    coalesce((
      select sum(greatest(credit_delta, 0))::integer
      from public.credit_ledger
      where user_id = p_user_id
        and ledger_kind = 'topup'
    ), 0) as total_topup_credits;
$$;

create or replace function public.compute_usage_credits(
  p_usage_kind text,
  p_provider text,
  p_quantity numeric
)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_rule public.billing_pricing_rules%rowtype;
  v_units numeric;
begin
  select *
  into v_rule
  from public.billing_pricing_rules
  where usage_kind = p_usage_kind
    and provider = p_provider
    and is_active = true
  order by created_at asc
  limit 1;

  if not found then
    raise exception 'pricing_rule_not_found'
      using errcode = 'P0001';
  end if;

  v_units := ceil(greatest(coalesce(p_quantity, 0), 0) / v_rule.unit_size);

  return greatest(
    v_rule.minimum_credits,
    greatest(v_units::integer, 0) * v_rule.credits_per_unit
  );
end;
$$;

create or replace function public.begin_managed_usage(
  p_user_id uuid,
  p_request_id text,
  p_usage_kind text,
  p_provider text default 'openai',
  p_quantity numeric default 0
)
returns table (
  allowed boolean,
  reason text,
  retry_after_seconds integer,
  request_id text,
  usage_event_id uuid,
  balance_credits integer,
  reserved_credits integer,
  usage_kind text,
  provider text,
  quantity numeric
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_account public.billing_accounts%rowtype;
  v_reserved_credits integer := 0;
  v_usage_request_id text;
  v_credit_ledger_id uuid := null;
  v_usage_event_id uuid := null;
  v_balance_after integer := 0;
begin
  if p_usage_kind not in ('asr', 'rewrite') then
    raise exception 'invalid_usage_kind'
      using errcode = '22023';
  end if;

  select *
  into v_account
  from public.ensure_billing_account(p_user_id);
  v_reserved_credits := public.compute_usage_credits(p_usage_kind, p_provider, p_quantity);
  v_usage_request_id := p_request_id || ':' || p_usage_kind;

  if v_account.balance_credits < v_reserved_credits then
    return query
    select
      false,
      'insufficient_credits',
      null::integer,
      v_usage_request_id,
      null::uuid,
      v_account.balance_credits,
      v_reserved_credits,
      p_usage_kind,
      p_provider,
      p_quantity;
    return;
  end if;

  update public.billing_accounts
  set balance_credits = billing_accounts.balance_credits - v_reserved_credits
  where billing_accounts.user_id = p_user_id
  returning billing_accounts.balance_credits into v_balance_after;

  insert into public.credit_ledger (
    user_id,
    account_id,
    ledger_kind,
    usage_kind,
    request_id,
    external_reference,
    credit_delta,
    balance_after,
    quantity,
    provider,
    metadata
  )
  values (
    p_user_id,
    p_user_id,
    'usage',
    p_usage_kind,
    v_usage_request_id,
    v_usage_request_id,
    -v_reserved_credits,
    v_balance_after,
    p_quantity,
    p_provider,
    jsonb_build_object('top_level_request_id', p_request_id, 'reserved_credits', v_reserved_credits)
  )
  returning id into v_credit_ledger_id;

  insert into public.usage_events (
    request_id,
    user_id,
    route_kind,
    usage_kind,
    request_units,
    billable_quantity,
    transcription_chars,
    reserved_credits,
    billed_credits,
    provider,
    billing_account_id,
    credit_ledger_id,
    status,
    metadata
  )
  values (
    v_usage_request_id,
    p_user_id,
    'audio_transcriptions',
    p_usage_kind,
    1,
    p_quantity,
    0,
    v_reserved_credits,
    v_reserved_credits,
    p_provider,
    p_user_id,
    v_credit_ledger_id,
    'reserved',
    jsonb_build_object('top_level_request_id', p_request_id)
  )
  returning id into v_usage_event_id;

  return query
  select
    true,
    null::text,
    null::integer,
    v_usage_request_id,
    v_usage_event_id,
    v_balance_after,
    v_reserved_credits,
    p_usage_kind,
    p_provider,
    p_quantity;
end;
$$;

create or replace function public.finalize_managed_usage(
  p_usage_event_id uuid,
  p_actual_quantity numeric,
  p_transcription_chars integer,
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
    billable_quantity = greatest(coalesce(p_actual_quantity, 0), 0),
    transcription_chars = greatest(coalesce(p_transcription_chars, 0), 0),
    upstream_status = p_upstream_status,
    status = 'completed',
    finalized_at = timezone('utc', now())
  where id = p_usage_event_id
    and status = 'reserved';

  if not found then
    raise exception 'usage_event_not_found'
      using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.refund_managed_usage(
  p_usage_event_id uuid,
  p_upstream_status integer default null
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_event public.usage_events%rowtype;
  v_balance_after integer := 0;
  v_refund_request_id text;
  v_ledger_id uuid;
begin
  select *
  into v_event
  from public.usage_events
  where id = p_usage_event_id
  for update;

  if not found then
    raise exception 'usage_event_not_found'
      using errcode = 'P0002';
  end if;

  if v_event.status = 'refunded' then
    return;
  end if;

  if v_event.status <> 'reserved' then
    return;
  end if;

  v_refund_request_id := v_event.request_id || ':refund';

  update public.billing_accounts
  set balance_credits = billing_accounts.balance_credits + v_event.reserved_credits
  where billing_accounts.user_id = v_event.user_id
  returning billing_accounts.balance_credits into v_balance_after;

  insert into public.credit_ledger (
    user_id,
    account_id,
    ledger_kind,
    usage_kind,
    request_id,
    external_reference,
    credit_delta,
    balance_after,
    quantity,
    provider,
    metadata
  )
  values (
    v_event.user_id,
    v_event.billing_account_id,
    'refund',
    v_event.usage_kind,
    v_refund_request_id,
    v_refund_request_id,
    v_event.reserved_credits,
    v_balance_after,
    v_event.billable_quantity,
    v_event.provider,
    jsonb_build_object(
      'usage_event_id', v_event.id,
      'top_level_request_id', v_event.metadata ->> 'top_level_request_id',
      'reserved_credits', v_event.reserved_credits
    )
  )
  returning id into v_ledger_id;

  update public.usage_events
  set
    billed_credits = 0,
    upstream_status = p_upstream_status,
    status = 'refunded',
    credit_ledger_id = v_ledger_id,
    refunded_at = timezone('utc', now())
  where id = p_usage_event_id;
end;
$$;

create or replace function public.apply_credit_topup(
  p_user_id uuid,
  p_credits integer,
  p_external_reference text,
  p_metadata jsonb default '{}'::jsonb,
  p_provider text default 'stripe'
)
returns table (
  balance_credits integer,
  ledger_id uuid
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_account public.billing_accounts%rowtype;
  v_existing_ledger public.credit_ledger%rowtype;
  v_new_balance integer;
  v_ledger_id uuid;
begin
  if p_credits <= 0 then
    raise exception 'invalid_topup_amount'
      using errcode = '22023';
  end if;

  select *
  into v_account
  from public.ensure_billing_account(p_user_id);

  select *
  into v_existing_ledger
  from public.credit_ledger
  where external_reference = p_external_reference
  limit 1;

  if found then
    return query select v_account.balance_credits, v_existing_ledger.id;
    return;
  end if;

  update public.billing_accounts as accounts
  set balance_credits = accounts.balance_credits + p_credits
  where accounts.user_id = p_user_id
  returning accounts.balance_credits into v_new_balance;

  insert into public.credit_ledger (
    user_id,
    account_id,
    ledger_kind,
    external_reference,
    credit_delta,
    balance_after,
    quantity,
    provider,
    metadata
  )
  values (
    p_user_id,
    p_user_id,
    'topup',
    p_external_reference,
    p_credits,
    v_new_balance,
    p_credits,
    p_provider,
    p_metadata
  )
  returning id into v_ledger_id;

  return query select v_new_balance, v_ledger_id;
end;
$$;

drop function if exists public.begin_managed_transcription_usage(uuid, text, text);

create or replace function public.begin_managed_transcription_usage(
  p_user_id uuid,
  p_request_id text,
  p_provider text default 'openai',
  p_audio_duration_seconds numeric default 0
)
returns table (
  allowed boolean,
  reason text,
  retry_after_seconds integer,
  request_id text,
  usage_event_id uuid,
  balance_credits integer,
  reserved_credits integer,
  usage_kind text,
  provider text,
  quantity numeric
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  return query
  select *
  from public.begin_managed_usage(
    p_user_id,
    p_request_id,
    'asr',
    p_provider,
    p_audio_duration_seconds
  );
end;
$$;

drop function if exists public.finalize_managed_transcription_usage(uuid, integer, integer, integer);

create or replace function public.finalize_managed_transcription_usage(
  p_usage_event_id uuid,
  p_transcription_chars integer,
  p_actual_quantity numeric,
  p_upstream_status integer
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  perform public.finalize_managed_usage(
    p_usage_event_id,
    p_actual_quantity,
    p_transcription_chars,
    p_upstream_status
  );
end;
$$;

drop function if exists public.get_managed_usage_summary(uuid);

create or replace function public.get_managed_usage_summary(p_user_id uuid)
returns table (
  balance_credits integer,
  recent_usage_credits_7d integer,
  recent_topup_credits_7d integer,
  total_usage_credits integer,
  total_topup_credits integer
)
language sql
security definer
set search_path = public, auth
as $$
  select *
  from public.get_managed_wallet_summary(p_user_id);
$$;
