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
