-- Persistent reactions for public SL RELAX chat. One reaction per user per message.
create table if not exists public.chat_message_reactions (
  message_id bigint not null references public.chat_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null check (emoji in ('❤️', '😂', '👍', '👎')),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

alter table public.chat_message_reactions enable row level security;
grant select on public.chat_message_reactions to anon, authenticated;
grant insert (message_id, user_id, emoji) on public.chat_message_reactions to authenticated;
grant update (emoji) on public.chat_message_reactions to authenticated;
grant delete on public.chat_message_reactions to authenticated;

drop policy if exists "chat reactions readable" on public.chat_message_reactions;
create policy "chat reactions readable" on public.chat_message_reactions
  for select to anon, authenticated using (true);

drop policy if exists "users insert own chat reactions" on public.chat_message_reactions;
create policy "users insert own chat reactions" on public.chat_message_reactions
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "users update own chat reactions" on public.chat_message_reactions;
create policy "users update own chat reactions" on public.chat_message_reactions
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "users delete own chat reactions" on public.chat_message_reactions;
create policy "users delete own chat reactions" on public.chat_message_reactions
  for delete to authenticated using (auth.uid() = user_id);
