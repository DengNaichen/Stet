alter table public.billing_accounts
  alter column managed_enabled set default false;

alter table public.credit_ledger
  drop constraint if exists credit_ledger_provider_check;

alter table public.credit_ledger
  add constraint credit_ledger_provider_check
  check (provider in ('openai', 'groq', 'stripe', 'manual'));

create or replace function public.begin_managed_usage(
  p_user_id uuid,
  p_request_id text,
  p_usage_kind text,
  p_provider text default 'openai',
  p_model_id text default null,
  p_quantity numeric default 0,
  p_reserved_credits integer default 0,
  p_request_metadata jsonb default '{}'::jsonb,
  p_max_requests_per_minute integer default 6,
  p_max_concurrent_requests integer default 2,
  p_daily_credit_limit integer default 1500
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
  v_usage_request_id text;
  v_credit_ledger_id uuid := null;
  v_usage_event_id uuid := null;
  v_balance_after integer := 0;
  v_recent_request_count integer := 0;
  v_concurrent_request_count integer := 0;
  v_daily_credits_used integer := 0;
begin
  if p_usage_kind not in ('asr', 'rewrite') then
    raise exception 'invalid_usage_kind'
      using errcode = '22023';
  end if;

  if p_reserved_credits <= 0 then
    raise exception 'invalid_reserved_credits'
      using errcode = '22023';
  end if;

  select *
  into v_account
  from public.ensure_billing_account(p_user_id);
  v_usage_request_id := p_request_id || ':' || p_usage_kind;

  if not coalesce(v_account.managed_enabled, false) then
    return query
    select
      false,
      'account_disabled',
      null::integer,
      v_usage_request_id,
      null::uuid,
      v_account.balance_credits,
      p_reserved_credits,
      p_usage_kind,
      p_provider,
      p_quantity;
    return;
  end if;

  if coalesce(p_max_requests_per_minute, 0) > 0 then
    select count(*)::integer
    into v_recent_request_count
    from public.usage_events
    where user_id = p_user_id
      and usage_kind = 'asr'
      and created_at >= timezone('utc', now()) - interval '1 minute';

    if v_recent_request_count >= p_max_requests_per_minute then
      return query
      select
        false,
        'request_limit_exceeded',
        60,
        v_usage_request_id,
        null::uuid,
        v_account.balance_credits,
        p_reserved_credits,
        p_usage_kind,
        p_provider,
        p_quantity;
      return;
    end if;
  end if;

  if coalesce(p_max_concurrent_requests, 0) > 0 then
    select count(*)::integer
    into v_concurrent_request_count
    from public.usage_events
    where user_id = p_user_id
      and status = 'reserved';

    if v_concurrent_request_count >= p_max_concurrent_requests then
      return query
      select
        false,
        'request_limit_exceeded',
        15,
        v_usage_request_id,
        null::uuid,
        v_account.balance_credits,
        p_reserved_credits,
        p_usage_kind,
        p_provider,
        p_quantity;
      return;
    end if;
  end if;

  if coalesce(p_daily_credit_limit, 0) > 0 then
    select coalesce(sum(
      case
        when ledger_kind in ('usage', 'adjustment') then greatest(-credit_delta, 0)
        when ledger_kind = 'refund' then -greatest(credit_delta, 0)
        else 0
      end
    ), 0)::integer
    into v_daily_credits_used
    from public.credit_ledger
    where user_id = p_user_id
      and created_at >= date_trunc('day', timezone('utc', now()));

    if v_daily_credits_used + p_reserved_credits > p_daily_credit_limit then
      return query
      select
        false,
        'request_limit_exceeded',
        3600,
        v_usage_request_id,
        null::uuid,
        v_account.balance_credits,
        p_reserved_credits,
        p_usage_kind,
        p_provider,
        p_quantity;
      return;
    end if;
  end if;

  if v_account.balance_credits < p_reserved_credits then
    return query
    select
      false,
      'insufficient_credits',
      null::integer,
      v_usage_request_id,
      null::uuid,
      v_account.balance_credits,
      p_reserved_credits,
      p_usage_kind,
      p_provider,
      p_quantity;
    return;
  end if;

  update public.billing_accounts as accounts
  set balance_credits = accounts.balance_credits - p_reserved_credits
  where accounts.user_id = p_user_id
  returning accounts.balance_credits into v_balance_after;

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
    -p_reserved_credits,
    v_balance_after,
    p_quantity,
    p_provider,
    jsonb_build_object(
      'top_level_request_id', p_request_id,
      'reserved_credits', p_reserved_credits,
      'model_id', p_model_id,
      'quantity', p_quantity
    ) || coalesce(p_request_metadata, '{}'::jsonb)
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
    estimated_credits,
    reserved_credits,
    billed_credits,
    input_tokens,
    output_tokens,
    provider,
    model_id,
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
    p_reserved_credits,
    p_reserved_credits,
    0,
    0,
    0,
    p_provider,
    p_model_id,
    p_user_id,
    v_credit_ledger_id,
    'reserved',
    jsonb_build_object(
      'top_level_request_id', p_request_id,
      'model_id', p_model_id,
      'reserved_credits', p_reserved_credits
    ) || coalesce(p_request_metadata, '{}'::jsonb)
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
    p_reserved_credits,
    p_usage_kind,
    p_provider,
    p_quantity;
end;
$$;
