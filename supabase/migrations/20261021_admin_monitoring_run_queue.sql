create table if not exists public.github_monitoring_run_queue (
  id uuid primary key default gen_random_uuid(),
  requested_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','running','success','failure','cancelled')),
  requested_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  workflow_run_id bigint,
  workflow_run_url text,
  result_summary text,
  updated_at timestamptz not null default now()
);

create index if not exists github_monitoring_run_queue_pending_idx
  on public.github_monitoring_run_queue (requested_at)
  where status = 'pending';

alter table public.github_monitoring_run_queue enable row level security;

revoke all on public.github_monitoring_run_queue from anon, authenticated;
grant all on public.github_monitoring_run_queue to service_role;

comment on table public.github_monitoring_run_queue is
  'Queue for Admin-requested Playwright website checks. Access only through the authenticated monitoring Edge Function and server-side worker.';
