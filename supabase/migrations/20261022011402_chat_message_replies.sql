-- Telegram-style quoted replies for public chat.
-- The quoted author/text are populated by a trusted trigger from the referenced row,
-- never accepted from the browser as authoritative snapshot data.

alter table public.chat_messages
  add column if not exists reply_to_id bigint,
  add column if not exists reply_to_name text,
  add column if not exists reply_to_message text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'chat_messages_reply_to_id_fkey'
      and conrelid = 'public.chat_messages'::regclass
  ) then
    alter table public.chat_messages
      add constraint chat_messages_reply_to_id_fkey
      foreign key (reply_to_id)
      references public.chat_messages(id)
      on delete set null;
  end if;
end;
$$;

create or replace function public.set_chat_reply_quote()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  original_name text;
  original_message text;
  original_hidden boolean;
begin
  if new.reply_to_id is null then
    new.reply_to_name := null;
    new.reply_to_message := null;
    return new;
  end if;

  select sender_name, message, is_hidden
    into original_name, original_message, original_hidden
    from public.chat_messages
   where id = new.reply_to_id;

  if not found or original_hidden then
    raise exception 'Pesan yang dibalas tidak tersedia.'
      using errcode = '23503';
  end if;

  new.reply_to_name := left(original_name, 60);
  new.reply_to_message := original_message;
  return new;
end;
$$;

revoke all on function public.set_chat_reply_quote() from public, anon, authenticated;

drop trigger if exists set_chat_reply_quote_before_insert on public.chat_messages;
create trigger set_chat_reply_quote_before_insert
before insert on public.chat_messages
for each row execute function public.set_chat_reply_quote();

-- Keep message text and the reply target as the only browser-writable fields.
grant insert (message, reply_to_id) on table public.chat_messages to authenticated;
