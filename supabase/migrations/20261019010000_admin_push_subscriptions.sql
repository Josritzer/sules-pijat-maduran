-- Admin-only Web Push endpoints. Apply to production only after explicit approval.
create table if not exists public.admin_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint admin_push_subscriptions_admin_endpoint_key unique (admin_id, endpoint)
);

alter table public.admin_push_subscriptions enable row level security;
revoke all on table public.admin_push_subscriptions from anon;
revoke all on table public.admin_push_subscriptions from authenticated;
grant select, insert, update, delete on table public.admin_push_subscriptions to authenticated;
grant all on table public.admin_push_subscriptions to service_role;

drop policy if exists "admin manages own push subscriptions" on public.admin_push_subscriptions;
create policy "admin manages own push subscriptions"
on public.admin_push_subscriptions
for all
to authenticated
using (
  admin_id = auth.uid()
  and exists (select 1 from public.admins a where a.id = auth.uid())
)
with check (
  admin_id = auth.uid()
  and exists (select 1 from public.admins a where a.id = auth.uid())
);

create index if not exists admin_push_subscriptions_admin_id_idx
  on public.admin_push_subscriptions(admin_id);
