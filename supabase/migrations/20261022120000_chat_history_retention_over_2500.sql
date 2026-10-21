-- Keep public chat history bounded without running cleanup in visitor browsers.
-- When total messages exceed 2,500, delete the 1,000 oldest rows.
-- chat_message_owners rows are removed through the existing ON DELETE CASCADE FK.

create index if not exists chat_messages_created_at_id_idx
  on public.chat_messages (created_at asc, id asc);

create or replace function public.trim_chat_history_after_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  message_count bigint;
begin
  -- Serialize retention checks so concurrent sends cannot skip the threshold.
  perform pg_advisory_xact_lock(736241905);

  select count(*) into message_count
  from public.chat_messages;

  if message_count > 2500 then
    delete from public.chat_messages as cm
    where cm.id in (
      select id
      from public.chat_messages
      order by created_at asc, id asc
      limit 1000
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trim_chat_history_after_insert on public.chat_messages;
create trigger trim_chat_history_after_insert
after insert on public.chat_messages
for each row
execute function public.trim_chat_history_after_insert();

revoke all on function public.trim_chat_history_after_insert() from public, anon, authenticated;
