-- 1. Drop the non-negative balance constraint to allow post-paid precision settlement
alter table public.billing_accounts drop constraint if exists billing_accounts_balance_credits_check;

-- 2. Replace finalize_managed_usage to remove the exception on insufficient credits
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
      -- Deduct normally unconditionally, allowing the balance to go into the negative
      update public.billing_accounts as accounts
      set balance_credits = accounts.balance_credits - v_delta
      where accounts.user_id = v_event.user_id
      returning accounts.balance_credits into v_balance_after;
    else
      update public.billing_accounts as accounts
      set balance_credits = accounts.balance_credits + abs(v_delta)
      where accounts.user_id = v_event.user_id
      returning accounts.balance_credits into v_balance_after;
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
