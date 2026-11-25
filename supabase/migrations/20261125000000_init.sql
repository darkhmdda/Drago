-- FinanSync · esquema inicial para Supabase (PostgreSQL)
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
  frequency     recurrence_freq not null,
  interval_days int check (interval_days > 0),          -- solo para 'custom'
  weekday       int check (weekday between 1 and 7),    -- semanal
  day_of_month  int check (day_of_month between 1 and 31),
  starts_on     date not null,
  ends_on       date,
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
  status         scheduled_status not null default 'expected'
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
  category_id        uuid references categories on delete set null,
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
