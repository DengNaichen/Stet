alter table public.usage_events
  add column if not exists model_id text;

alter table public.usage_events
  add column if not exists estimated_credits integer not null default 0 check (estimated_credits >= 0);

alter table public.usage_events
  add column if not exists input_tokens integer not null default 0 check (input_tokens >= 0);

alter table public.usage_events
  add column if not exists output_tokens integer not null default 0 check (output_tokens >= 0);

create or replace function public.begin_managed_usage(
  p_user_id uuid,
  p_request_id text,
  p_usage_kind text,
  p_provider text default 'openai',
  p_model_id text default null,
  p_quantity numeric default 0,
  p_reserved_credits integer default 0
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

  update public.billing_accounts
  set balance_credits = balance_credits - p_reserved_credits
  where user_id = p_user_id
  returning balance_credits into v_balance_after;

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
    )
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
    )
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

create or replace function public.finalize_managed_usage(
  p_usage_event_id uuid,
  p_actual_quantity numeric,
  p_billed_credits integer,
  p_transcription_chars integer,
  p_input_tokens integer,
  p_output_tokens integer,
  p_upstream_status integer
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_event public.usage_events%rowtype;
  v_account public.billing_accounts%rowtype;
  v_actual_credits integer := 0;
  v_delta integer := 0;
  v_balance_after integer := 0;
  v_adjustment_ledger_id uuid;
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

  if v_event.status <> 'reserved' then
    return;
  end if;

  v_actual_credits := greatest(coalesce(p_billed_credits, 0), 0);
  v_delta := v_actual_credits - v_event.reserved_credits;

  if v_delta <> 0 then
    select *
    into v_account
    from public.billing_accounts
    where user_id = v_event.user_id
    for update;

    if v_delta > 0 then
      if v_account.balance_credits < v_delta then
        raise exception 'insufficient_finalize_credits'
          using errcode = 'P0001';
      end if;

      update public.billing_accounts
      set balance_credits = balance_credits - v_delta
      where user_id = v_event.user_id
      returning balance_credits into v_balance_after;
    else
      update public.billing_accounts
      set balance_credits = balance_credits + abs(v_delta)
      where user_id = v_event.user_id
      returning balance_credits into v_balance_after;
    end if;

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
      'adjustment',
      v_event.usage_kind,
      v_event.request_id || ':settlement',
      v_event.request_id || ':settlement',
      -v_delta,
      v_balance_after,
      greatest(coalesce(p_actual_quantity, 0), 0),
      v_event.provider,
      jsonb_build_object(
        'usage_event_id', v_event.id,
        'top_level_request_id', v_event.metadata ->> 'top_level_request_id',
        'reserved_credits', v_event.reserved_credits,
        'actual_credits', v_actual_credits,
        'delta_credits', v_delta,
        'model_id', v_event.model_id,
        'input_tokens', greatest(coalesce(p_input_tokens, 0), 0),
        'output_tokens', greatest(coalesce(p_output_tokens, 0), 0)
      )
    )
    returning id into v_adjustment_ledger_id;
  end if;

  update public.usage_events
  set
    billable_quantity = greatest(coalesce(p_actual_quantity, 0), 0),
    transcription_chars = greatest(coalesce(p_transcription_chars, 0), 0),
    input_tokens = greatest(coalesce(p_input_tokens, 0), 0),
    output_tokens = greatest(coalesce(p_output_tokens, 0), 0),
    estimated_credits = v_event.reserved_credits,
    billed_credits = v_actual_credits,
    upstream_status = p_upstream_status,
    status = 'completed',
    credit_ledger_id = coalesce(v_adjustment_ledger_id, v_event.credit_ledger_id),
    finalized_at = timezone('utc', now()),
    metadata = v_event.metadata || jsonb_build_object(
      'actual_credits', v_actual_credits,
      'input_tokens', greatest(coalesce(p_input_tokens, 0), 0),
      'output_tokens', greatest(coalesce(p_output_tokens, 0), 0)
    )
  where id = p_usage_event_id;
end;
$$;

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
declare
  v_reserved_credits integer := greatest(ceil(coalesce(p_audio_duration_seconds, 0))::integer, 1);
begin
  return query
  select *
  from public.begin_managed_usage(
    p_user_id,
    p_request_id,
    'asr',
    p_provider,
    null,
    p_audio_duration_seconds,
    v_reserved_credits
  );
end;
$$;

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
    greatest(ceil(coalesce(p_actual_quantity, 0))::integer, 1),
    p_transcription_chars,
    0,
    0,
    p_upstream_status
  );
end;
$$;
