-- Keep account-to-message links out of the exposed public API schema.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

alter table public.chat_message_owners set schema private;

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
  insert into private.chat_message_owners (message_id, sender_id)
  values (new.id, auth.uid());
  return new;
end;
$$;
revoke all on function public.record_chat_message_owner() from public, anon, authenticated;
