-- Store the latest website monitor result for the Admin dashboard only.
-- GitHub Actions and the Edge Function service role are the only database writers/readers.
create table if not exists public.github_monitoring_status (
  id smallint primary key default 1 check (id = 1),
  status text not null check (status in ('success', 'failure')),
  checked_at timestamptz not null,
  workflow_run_id bigint,
  workflow_run_url text,
  commit_sha text,
  http_status integer,
  duration_seconds numeric(10,1),
  summary text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.github_monitoring_status enable row level security;
revoke all on table public.github_monitoring_status from anon, authenticated;
grant all on table public.github_monitoring_status to service_role;
