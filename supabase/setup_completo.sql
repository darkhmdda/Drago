-- Drago · script completo para el SQL Editor de Supabase
-- Generado a partir de supabase/migrations (no editar a mano). Ejecutar UNA sola vez en un proyecto nuevo.

-- Drago · esquema inicial para Supabase (PostgreSQL)
-- Reglas: UUID como identificadores, claves foráneas, dinero en centavos
-- enteros (bigint, nunca float), RLS por usuario y auditoría.
-- Este esquema refleja el modelo de lib/domain/models.dart; la app v0.2 aún
-- guarda localmente y la sincronización se activará en una versión posterior.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------
create type account_kind      as enum ('physical', 'digital');
create type tx_type           as enum ('income', 'expense', 'debt_payment', 'transfer', 'adjustment');
create type debt_status       as enum ('active', 'settled', 'cancelled');
create type scheduled_status  as enum ('expected', 'received', 'not_received');
create type recurrence_freq   as enum ('daily', 'weekly', 'biweekly', 'monthly', 'custom');
create type notification_status as enum ('pending', 'sent', 'cancelled');

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------
create table accounts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  name        text not null check (length(trim(name)) > 0),
  kind        account_kind not null,
  archived    boolean not null default false,
  created_at  timestamptz not null default now()
);

create table categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  name        text not null,
  is_income   boolean not null default false,
  unique (user_id, name, is_income)
);

create table debts (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users on delete cascade,
  name         text not null check (length(trim(name)) > 0),
  total_cents  bigint not null check (total_cents > 0),
  start_date   date not null,
  description  text not null default '',
  status       debt_status not null default 'active',
  created_at   timestamptz not null default now()
);

create table installments (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users on delete cascade,
  debt_id       uuid not null references debts on delete cascade,
  number        int  not null check (number > 0),
  amount_cents  bigint not null check (amount_cents > 0),
  due_date      date not null,
  cancelled     boolean not null default false
);
create index on installments (debt_id, due_date);

create table recurrences (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users on delete cascade,
  description   text not null,
  amount_cents  bigint not null check (amount_cents > 0),
  account_id    uuid not null references accounts,
  is_income     boolean not null default true,
  frequency     recurrence_freq not null,
  interval_days int not null default 7 check (interval_days > 0),  -- solo para 'custom'
  starts_on     date not null,   -- define el día de la semana / del mes
  ends_on       date check (ends_on is null or ends_on >= starts_on),
  active        boolean not null default true
);

-- Ingresos (y gastos) previstos. Nunca afectan el saldo real.
create table scheduled_items (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users on delete cascade,
  recurrence_id  uuid references recurrences on delete set null,
  is_income      boolean not null default true,
  date           date not null,
  amount_cents   bigint not null check (amount_cents > 0),
  description    text not null,
  account_id     uuid not null references accounts,
  status         scheduled_status not null default 'expected',
  -- Ocurrencia de una regla recurrente que el usuario confirmó o ajustó.
  occurrence_date date,
  unique (recurrence_id, occurrence_date)   -- una ocurrencia nunca se duplica
);

-- Movimientos reales. amount_cents > 0 salvo en ajustes (con signo).
create table transactions (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null default auth.uid() references auth.users on delete cascade,
  date               date not null,
  amount_cents       bigint not null,
  type               tx_type not null,
  description        text not null default '',
  account_id         uuid not null references accounts,
  to_account_id      uuid references accounts,
  category           text,
  debt_id            uuid references debts on delete restrict,
  installment_id     uuid references installments on delete restrict,
  scheduled_item_id  uuid references scheduled_items on delete set null,
  created_at         timestamptz not null default now(),
  check (type = 'adjustment' or amount_cents > 0),
  check (amount_cents <> 0),
  check ((type = 'transfer') = (to_account_id is not null)),
  check (to_account_id is null or to_account_id <> account_id),
  check (type <> 'debt_payment' or (debt_id is not null and installment_id is not null))
);
create index on transactions (user_id, date desc);
create index on transactions (installment_id);

-- Abonos a cuotas: vínculo explícito entre una cuota y el movimiento real.
create table installment_payments (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users on delete cascade,
  installment_id  uuid not null references installments on delete restrict,
  transaction_id  uuid not null unique references transactions on delete cascade,
  amount_cents    bigint not null check (amount_cents > 0)
);

alter table scheduled_items add column transaction_id uuid references transactions on delete set null;

create table projections (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now()
);

create table projection_events (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users on delete cascade,
  projection_id  uuid not null references projections on delete cascade,
  date           date not null,
  amount_cents   bigint not null,   -- + ingreso, - gasto
  description    text not null
);

create table notifications (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users on delete cascade,
  installment_id  uuid references installments on delete cascade,
  notify_at       timestamptz not null,
  title           text not null,
  body            text not null,
  status          notification_status not null default 'pending',
  unique (installment_id, notify_at)   -- evita recordatorios duplicados
);

create table attachments (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users on delete cascade,
  storage_path    text not null,
  transaction_id  uuid references transactions on delete set null,
  debt_id         uuid references debts on delete set null,
  created_at      timestamptz not null default now()
);

create table audit_logs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  at          timestamptz not null default now(),
  action      text not null,
  details     text not null default ''
);

-- ---------------------------------------------------------------------------
-- Seguridad: cada usuario solo ve y modifica sus propios registros (RLS)
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['accounts','categories','debts','installments','recurrences','scheduled_items',
                           'transactions','installment_payments','projections','projection_events',
                           'notifications','attachments','audit_logs']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy "own rows" on %I for all using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end $$;

-- La bitácora no se edita ni se borra desde el cliente.
drop policy "own rows" on audit_logs;
create policy "read own audit" on audit_logs for select using (user_id = auth.uid());
create policy "insert own audit" on audit_logs for insert with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Saldos (solo dinero real)
-- ---------------------------------------------------------------------------
create view account_balances with (security_invoker = true) as
select a.id as account_id, a.user_id, a.kind,
       coalesce(sum(case
         when t.type = 'income'                       and t.account_id = a.id then t.amount_cents
         when t.type in ('expense','debt_payment')    and t.account_id = a.id then -t.amount_cents
         when t.type = 'adjustment'                   and t.account_id = a.id then t.amount_cents
         when t.type = 'transfer' and t.account_id = a.id    then -t.amount_cents
         when t.type = 'transfer' and t.to_account_id = a.id then t.amount_cents
       end), 0)::bigint as balance_cents
from accounts a
left join transactions t on t.account_id = a.id or t.to_account_id = a.id
group by a.id;

-- ---------------------------------------------------------------------------
-- Pago de cuota atómico: valida, registra el movimiento y el abono, cancela
-- recordatorios y actualiza el estado de la deuda en una sola transacción.
-- ---------------------------------------------------------------------------
create or replace function pay_installment(
  p_installment_id uuid, p_account_id uuid, p_date date, p_amount_cents bigint default null
) returns uuid
language plpgsql security invoker as $$
declare
  v_inst installments%rowtype;
  v_debt debts%rowtype;
  v_paid bigint;
  v_remaining bigint;
  v_amount bigint;
  v_tx uuid;
begin
  select * into v_inst from installments where id = p_installment_id for update;
  if not found then raise exception 'La cuota no existe'; end if;
  select * into v_debt from debts where id = v_inst.debt_id for update;
  if v_debt.status = 'cancelled' then raise exception 'La deuda está cancelada'; end if;
  if v_inst.cancelled then raise exception 'La cuota está cancelada'; end if;
  perform 1 from accounts where id = p_account_id;
  if not found then raise exception 'La cuenta no existe'; end if;

  select coalesce(sum(amount_cents), 0) into v_paid from installment_payments where installment_id = v_inst.id;
  v_remaining := v_inst.amount_cents - v_paid;
  if v_remaining <= 0 then raise exception 'La cuota ya está pagada'; end if;
  v_amount := coalesce(p_amount_cents, v_remaining);
  if v_amount <= 0 or v_amount > v_remaining then raise exception 'Importe inválido'; end if;

  insert into transactions (date, amount_cents, type, description, account_id, debt_id, installment_id)
  values (p_date, v_amount, 'debt_payment', 'Pago ' || v_debt.name || ' · cuota ' || v_inst.number,
          p_account_id, v_debt.id, v_inst.id)
  returning id into v_tx;
  insert into installment_payments (installment_id, transaction_id, amount_cents) values (v_inst.id, v_tx, v_amount);

  if v_amount = v_remaining then
    update notifications set status = 'cancelled' where installment_id = v_inst.id and status = 'pending';
  end if;

  if not exists (
    select 1 from installments i
    where i.debt_id = v_debt.id and not i.cancelled
      and i.amount_cents > (select coalesce(sum(p.amount_cents), 0) from installment_payments p where p.installment_id = i.id)
  ) then
    update debts set status = 'settled' where id = v_debt.id;
  end if;

  insert into audit_logs (action, details)
  values ('Pago de cuota', v_debt.name || ' #' || v_inst.number || ': ' || v_amount || ' centavos');
  return v_tx;
end $$;

-- ---------------------------------------------------------------------------
-- Permisos explícitos: el proyecto se crea SIN conceder acceso automático a
-- tablas nuevas. Solo usuarios autenticados (y siempre filtrados por RLS).
-- El rol anónimo no recibe ningún permiso.
-- ---------------------------------------------------------------------------
grant usage on schema public to authenticated;
grant select, insert, update, delete on
  accounts, categories, debts, installments, recurrences, scheduled_items,
  transactions, installment_payments, projections, projection_events,
  notifications, attachments to authenticated;
grant select, insert on audit_logs to authenticated;
grant select on account_balances to authenticated;
grant execute on function pay_installment(uuid, uuid, date, bigint) to authenticated;
revoke execute on function pay_installment(uuid, uuid, date, bigint) from public, anon;

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

-- Drago · avisos en tiempo real
-- Cuando un dispositivo sube cambios, la versión en sync_state aumenta y
-- Supabase Realtime avisa al instante a los demás dispositivos del usuario.
-- RLS se aplica también a Realtime: cada usuario solo recibe sus propios avisos.
alter publication supabase_realtime add table sync_state;

-- Drago · simulaciones sincronizadas (v0.5)
-- Las simulaciones se guardan en la tabla projections (su definición en
-- formato JSON) y viajan con el resto de los datos en pull_ledger/push_ledger.

alter table projections add column if not exists definition jsonb not null default '{}'::jsonb;

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
    'scenarios', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'createdAt', created_at,
        'adjustments', coalesce(definition->'adjustments', '[]'::jsonb)) order by created_at, id)
      from projections where user_id = auth.uid()), '[]'::jsonb),
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
  delete from projections where user_id = v_uid;
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

  -- Simulaciones guardadas (solo su definición; nunca afectan datos reales).
  insert into projections (id, name, created_at, definition)
  select id, name, coalesce("createdAt", now()), jsonb_build_object('adjustments', coalesce(adjustments, '[]'::jsonb))
  from jsonb_to_recordset(coalesce(p_data->'scenarios', '[]'))
    as x(id uuid, name text, "createdAt" timestamptz, adjustments jsonb);

  -- La bitácora solo crece: se agregan entradas nuevas, nunca se borran.
  insert into audit_logs (id, at, action, details)
  select id, at, action, coalesce(details, '')
  from jsonb_to_recordset(coalesce(p_data->'auditLog', '[]')) as x(id uuid, at timestamptz, action text, details text)
  on conflict (id) do nothing;

  update sync_state set version = v_current + 1, device = p_device, updated_at = now() where user_id = v_uid;
  return v_current + 1;
end $$;


