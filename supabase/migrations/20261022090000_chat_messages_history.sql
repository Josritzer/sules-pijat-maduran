-- Persistent public chat. Public messages never expose a customer auth UUID.
create table if not exists public.chat_messages (
  id bigint generated always as identity primary key,
  sender_name text not null,
  message text not null check (char_length(btrim(message)) between 1 and 240),
  is_hidden boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_visible_created_at_idx
  on public.chat_messages (created_at desc)
  where is_hidden = false;

-- Private account-to-message mapping for future Admin moderation.
create table if not exists public.chat_message_owners (
  message_id bigint primary key references public.chat_messages(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.chat_message_owners enable row level security;
revoke all on table public.chat_message_owners from anon, authenticated;

alter table public.chat_messages enable row level security;
revoke all on table public.chat_messages from anon, authenticated;
grant select on table public.chat_messages to anon, authenticated;
grant insert (message) on table public.chat_messages to authenticated;
grant usage, select on sequence public.chat_messages_id_seq to authenticated;

drop policy if exists "chat messages visible to visitors" on public.chat_messages;
create policy "chat messages visible to visitors"
  on public.chat_messages for select
  to anon, authenticated
  using (is_hidden = false);

drop policy if exists "signed-in customers can send chat messages" on public.chat_messages;
create policy "signed-in customers can send chat messages"
  on public.chat_messages for insert
  to authenticated
  with check (is_hidden = false);

create or replace function public.set_chat_message_sender()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  profile_name text;
begin
  if auth.uid() is null then
    raise exception 'Login SL RELAX diperlukan untuk mengirim pesan.'
      using errcode = '42501';
  end if;

  select nullif(btrim(c.nama), '')
    into profile_name
    from public.customers as c
    where c.id = auth.uid();

  if profile_name is null or char_length(profile_name) < 2 then
    raise exception 'Lengkapi nama profil di menu Akun sebelum mengirim pesan.'
      using errcode = '23514';
  end if;

  new.sender_name := left(profile_name, 60);
  new.created_at := now();
  new.is_hidden := false;
  return new;
end;
$$;
revoke all on function public.set_chat_message_sender() from public, anon, authenticated;

create or replace function public.record_chat_message_owner()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Login SL RELAX diperlukan untuk mengirim pesan.'
      using errcode = '42501';
  end if;
  insert into public.chat_message_owners (message_id, sender_id)
  values (new.id, auth.uid());
  return new;
end;
$$;
revoke all on function public.record_chat_message_owner() from public, anon, authenticated;

drop trigger if exists set_chat_message_sender_before_insert on public.chat_messages;
create trigger set_chat_message_sender_before_insert
  before insert on public.chat_messages
  for each row execute function public.set_chat_message_sender();

drop trigger if exists record_chat_message_owner_after_insert on public.chat_messages;
create trigger record_chat_message_owner_after_insert
  after insert on public.chat_messages
  for each row execute function public.record_chat_message_owner();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'chat_messages'
     ) then
    alter publication supabase_realtime add table public.chat_messages;
  end if;
end;
$$;
