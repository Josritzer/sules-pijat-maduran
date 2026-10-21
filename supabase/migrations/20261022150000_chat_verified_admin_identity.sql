-- Mark messages authored by verified Admin accounts; customer names remain unchanged.
alter table public.chat_messages
  add column if not exists is_admin boolean not null default false;

create or replace function public.set_chat_message_sender()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  profile_name text;
begin
  if auth.uid() is null then
    raise exception 'Login SL RELAX diperlukan untuk mengirim pesan.'
      using errcode = '42501';
  end if;

  if exists (select 1 from public.admins where id = auth.uid()) then
    new.sender_name := 'Admin';
    new.is_admin := true;
  else
    select nullif(btrim(c.nama), '')
      into profile_name
      from public.customers as c
      where c.id = auth.uid();

    if profile_name is null or char_length(profile_name) < 2 then
      raise exception 'Lengkapi nama profil di menu Akun sebelum mengirim pesan.'
        using errcode = '23514';
    end if;

    new.sender_name := left(profile_name, 60);
    new.is_admin := false;
  end if;

  new.created_at := now();
  new.is_hidden := false;
  return new;
end;
$function$;

revoke all on function public.set_chat_message_sender() from public, anon, authenticated;

-- Re-label existing messages only when the private owner mapping verifies Admin authorship.
update public.chat_messages as cm
set sender_name = 'Admin',
    is_admin = true
from private.chat_message_owners as owner_map
join public.admins as a on a.id = owner_map.sender_id
where cm.id = owner_map.message_id;
