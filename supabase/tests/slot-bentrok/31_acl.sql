select p.proname, p.prosecdef as security_definer, p.provolatile as volatile_kind, pg_get_function_result(p.oid) as hasil_kolom, p.proconfig as config,
  has_function_privilege('anon', p.oid, 'execute') as anon,
  has_function_privilege('authenticated', p.oid, 'execute') as authenticated,
  has_function_privilege('public', p.oid, 'execute') as public_,
  p.proacl::text as acl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('get_slot_terisi','accept_booking') order by 1;
