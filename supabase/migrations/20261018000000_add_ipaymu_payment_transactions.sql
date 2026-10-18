-- iPaymu payment ledger (review/deploy separately; do not apply to production as part of this PR).
create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  customer_id uuid not null references auth.users(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'IDR' check (currency = 'IDR'),
  status text not null default 'PENDING'
    check (status in ('PENDING','PAID','FAILED','EXPIRED','CANCELLED')),
  ipaymu_session_id text unique,
  ipaymu_transaction_id text unique,
  checkout_url text,
  callback_signature_valid boolean not null default false,
  last_callback_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists payment_transactions_booking_created_idx
  on public.payment_transactions (booking_id, created_at desc);

create unique index if not exists payment_transactions_one_pending_per_booking_idx
  on public.payment_transactions (booking_id)
  where status = 'PENDING';

alter table public.payment_transactions enable row level security;
-- No direct client policies: all writes/reads go through authenticated Edge Functions.
