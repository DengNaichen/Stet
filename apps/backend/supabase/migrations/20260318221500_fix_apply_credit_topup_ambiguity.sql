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
