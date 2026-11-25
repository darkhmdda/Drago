-- Drago · sincronización entre dispositivos
--
-- La app guarda todo localmente (funciona sin conexión) y sincroniza el
-- estado completo del usuario con estas dos funciones:
--   pull_ledger()                      → devuelve todos sus datos como JSON
--   push_ledger(base_version, data)    → reemplaza sus datos de forma atómica
--
-- Control de versiones optimista: cada push indica sobre qué versión se hizo.
-- Si otro dispositivo subió cambios antes, el push se rechaza ('conflict') y
-- la app le pregunta al usuario qué copia conservar. Nunca se pierden datos
-- en silencio.
--
-- Ambas funciones son SECURITY INVOKER: se ejecutan con los permisos del
-- usuario y RLS limita todo a sus propias filas.

create table sync_state (
  user_id     uuid primary key default auth.uid() references auth.users on delete cascade,
  version     bigint not null default 0,
  device      text,
  updated_at  timestamptz not null default now()
);
alter table sync_state enable row level security;
create policy "own rows" on sync_state for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update on sync_state to authenticated;

-- camelCase (app) <-> snake_case (base de datos) para valores de enums.
create or replace function _snake(v text) returns text language sql immutable as
$$ select lower(regexp_replace(v, '([A-Z])', '_\1', 'g')) $$;
create or replace function _camel(v text) returns text language plpgsql immutable as $$
declare out text := ''; part text; i int := 0;
begin
  foreach part in array string_to_array(v, '_') loop
    out := out || case when i = 0 then part else upper(left(part, 1)) || substr(part, 2) end;
    i := i + 1;
  end loop;
  return out;
end $$;

create or replace function pull_ledger() returns jsonb
language sql stable security invoker as $$
  select jsonb_build_object(
    'schemaVersion', 2,
    'syncVersion', coalesce((select version from sync_state where user_id = auth.uid()), 0),
    'accounts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'kind', kind::text, 'archived', archived) order by created_at, id)
      from accounts where user_id = auth.uid()), '[]'::jsonb),
    'transactions', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'date', date, 'amount', amount_cents, 'type', _camel(type::text), 'description', description,
        'accountId', account_id, 'toAccountId', to_account_id, 'category', category, 'debtId', debt_id,
        'installmentId', installment_id, 'scheduledItemId', scheduled_item_id, 'createdAt', created_at) order by created_at, id)
      from transactions where user_id = auth.uid()), '[]'::jsonb),
    'debts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'total', total_cents, 'startDate', start_date, 'description', description,
        'status', status::text) order by created_at, id)
      from debts where user_id = auth.uid()), '[]'::jsonb),
    'installments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'debtId', debt_id, 'number', number, 'amount', amount_cents, 'dueDate', due_date,
        'cancelled', cancelled) order by debt_id, number)
      from installments where user_id = auth.uid()), '[]'::jsonb),
    'recurrences', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'description', description, 'amount', amount_cents, 'accountId', account_id,
        'isIncome', is_income, 'frequency', frequency::text, 'intervalDays', interval_days,
        'startDate', starts_on, 'endDate', ends_on, 'active', active) order by starts_on, id)
      from recurrences where user_id = auth.uid()), '[]'::jsonb),
    'scheduledItems', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'date', date, 'amount', amount_cents, 'description', description, 'accountId', account_id,
        'isIncome', is_income, 'status', _camel(status::text), 'transactionId', transaction_id,
        'recurrenceId', recurrence_id, 'occurrenceDate', occurrence_date) order by date, id)
      from scheduled_items where user_id = auth.uid()), '[]'::jsonb),
    'auditLog', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'at', at, 'action', action, 'details', details) order by at, id)
      from audit_logs where user_id = auth.uid()), '[]'::jsonb)
  )
$$;

create or replace function push_ledger(p_base_version bigint, p_data jsonb, p_device text default null)
returns bigint
language plpgsql security invoker as $$
declare
  v_uid uuid := auth.uid();
  v_current bigint;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- Bloquea la fila de versión del usuario para serializar pushes concurrentes.
  insert into sync_state (user_id, version) values (v_uid, 0) on conflict (user_id) do nothing;
  select version into v_current from sync_state where user_id = v_uid for update;
  if v_current <> p_base_version then
    raise exception 'conflict: la nube tiene la versión %, este dispositivo partió de la %', v_current, p_base_version
      using errcode = 'P0409';
  end if;

  -- Reemplazo completo dentro de esta transacción (todo o nada).
  delete from installment_payments where user_id = v_uid;
  update scheduled_items set transaction_id = null where user_id = v_uid;
  delete from transactions where user_id = v_uid;
  delete from scheduled_items where user_id = v_uid;
  delete from recurrences where user_id = v_uid;
  delete from installments where user_id = v_uid;
  delete from debts where user_id = v_uid;
  delete from accounts where user_id = v_uid;

  insert into accounts (id, name, kind, archived)
  select id, name, kind::account_kind, coalesce(archived, false)
  from jsonb_to_recordset(coalesce(p_data->'accounts', '[]')) as x(id uuid, name text, kind text, archived boolean);

  insert into debts (id, name, total_cents, start_date, description, status)
  select id, name, total, "startDate", coalesce(description, ''), status::debt_status
  from jsonb_to_recordset(coalesce(p_data->'debts', '[]'))
    as x(id uuid, name text, total bigint, "startDate" date, description text, status text);

  insert into installments (id, debt_id, number, amount_cents, due_date, cancelled)
  select id, "debtId", number, amount, "dueDate", coalesce(cancelled, false)
  from jsonb_to_recordset(coalesce(p_data->'installments', '[]'))
    as x(id uuid, "debtId" uuid, number int, amount bigint, "dueDate" date, cancelled boolean);

  insert into recurrences (id, description, amount_cents, account_id, is_income, frequency, interval_days, starts_on, ends_on, active)
  select id, description, amount, "accountId", coalesce("isIncome", true), frequency::recurrence_freq,
         coalesce("intervalDays", 7), "startDate", "endDate", coalesce(active, true)
  from jsonb_to_recordset(coalesce(p_data->'recurrences', '[]'))
    as x(id uuid, description text, amount bigint, "accountId" uuid, "isIncome" boolean, frequency text,
         "intervalDays" int, "startDate" date, "endDate" date, active boolean);

  insert into scheduled_items (id, date, amount_cents, description, account_id, is_income, status, recurrence_id, occurrence_date)
  select id, date, amount, description, "accountId", coalesce("isIncome", true), _snake(status)::scheduled_status,
         "recurrenceId", "occurrenceDate"
  from jsonb_to_recordset(coalesce(p_data->'scheduledItems', '[]'))
    as x(id uuid, date date, amount bigint, description text, "accountId" uuid, "isIncome" boolean, status text,
         "recurrenceId" uuid, "occurrenceDate" date);

  insert into transactions (id, date, amount_cents, type, description, account_id, to_account_id, category,
                            debt_id, installment_id, scheduled_item_id, created_at)
  select id, date, amount, _snake(type)::tx_type, coalesce(description, ''), "accountId", "toAccountId", category,
         "debtId", "installmentId", "scheduledItemId", coalesce("createdAt", now())
  from jsonb_to_recordset(coalesce(p_data->'transactions', '[]'))
    as x(id uuid, date date, amount bigint, type text, description text, "accountId" uuid, "toAccountId" uuid,
         category text, "debtId" uuid, "installmentId" uuid, "scheduledItemId" uuid, "createdAt" timestamptz);

  update scheduled_items s set transaction_id = x."transactionId"
  from jsonb_to_recordset(coalesce(p_data->'scheduledItems', '[]')) as x(id uuid, "transactionId" uuid)
  where s.id = x.id and s.user_id = v_uid and x."transactionId" is not null;

  -- Abonos derivados de los pagos de cuota (para consultas y para pay_installment).
  insert into installment_payments (installment_id, transaction_id, amount_cents)
  select installment_id, id, amount_cents from transactions
  where user_id = v_uid and type = 'debt_payment';

  -- La bitácora solo crece: se agregan entradas nuevas, nunca se borran.
  insert into audit_logs (id, at, action, details)
  select id, at, action, coalesce(details, '')
  from jsonb_to_recordset(coalesce(p_data->'auditLog', '[]')) as x(id uuid, at timestamptz, action text, details text)
  on conflict (id) do nothing;

  update sync_state set version = v_current + 1, device = p_device, updated_at = now() where user_id = v_uid;
  return v_current + 1;
end $$;

grant execute on function pull_ledger() to authenticated;
grant execute on function push_ledger(bigint, jsonb, text) to authenticated;
revoke execute on function pull_ledger() from public, anon;
revoke execute on function push_ledger(bigint, jsonb, text) from public, anon;
