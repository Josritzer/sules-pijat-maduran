\set ON_ERROR_STOP on
create schema t;
insert into admins values ('aaaaaaaa-0000-0000-0000-000000000001');
create function t.bk(p_tgl date, p_jam time, p_dur int, p_status booking_status) returns uuid language sql as $$
  insert into bookings(tanggal, jam_mulai, durasi_menit, status) values (p_tgl, p_jam, p_dur, p_status) returning id $$;
create function t.acc(p_id uuid) returns text language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001', false);
  r := public.accept_booking(p_id);
  return case when (r->>'success')::boolean then 'OK' else r->>'reason' end;
exception when others then return 'ERR:' || sqlerrm;
end $$;
create table t.hasil(grup text, nama text, harapan text, hasil text, lulus boolean);
