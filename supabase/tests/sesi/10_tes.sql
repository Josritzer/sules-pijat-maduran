\set ON_ERROR_STOP off
-- Tes buka/tutup sesi. Jalankan setelah 00_base.sql + migrasi slot, paket5, dan sesi.
create table hasil(no int, nama text, lulus boolean, bukti text);
create function try_book(p_tgl date, p_jam time, p_loc tipe_lokasi default 'DI_TEMPAT') returns text language plpgsql as $$
begin
  perform public.create_booking_server('11111111-1111-1111-1111-111111111111','Uji','081',
     '90m', 1::smallint, p_tgl, p_jam, p_loc);
  return 'OK';
exception when others then return sqlerrm; end $$;
create function ok(t text) returns boolean language sql as $$ select t = 'OK' $$;
create function ditolak(t text) returns boolean language sql as $$ select t <> 'OK' and t ilike 'Sesi %ditutup%' or t ilike 'Sesi %sedang ditutup%' $$;
create function set_sesi(p_sesi text, p_buka boolean, p_sampai date default null, p_pesan text default null) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',false);
  perform public.admin_set_sesi(p_sesi,p_buka,p_sampai,p_pesan); return 'OK';
exception when others then return sqlerrm; end $$;
insert into admins values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
create function reset() returns void language sql as $$
  update operational_settings set value='{"buka": true, "pesan": "", "sampai": null}' where key in ('sesi_pagi','sesi_malam'); $$;
create function hari() returns date language sql as $$ select timezone('Asia/Jakarta', now())::date $$;

-- 1. Sesi buka
select reset();
insert into hasil select 1,'Sesi buka: siang & malam bisa booking', ok(try_book(hari()+1,'10:00')) and ok(try_book(hari()+1,'20:00')), try_book(hari()+1,'10:00')||'/'||try_book(hari()+1,'20:00');

-- 2. Siang tutup tanpa batas / malam tutup (independen)
select reset(); select set_sesi('pagi', false);
insert into hasil select 2,'Siang tutup: siang ditolak, malam tetap bisa', ditolak(try_book(hari()+1,'10:00')) and ok(try_book(hari()+1,'20:00')), try_book(hari()+1,'10:00')||'/'||try_book(hari()+1,'20:00');
select reset(); select set_sesi('malam', false);
insert into hasil select 2,'Malam tutup: malam ditolak, siang tetap bisa', ditolak(try_book(hari()+1,'20:00')) and ok(try_book(hari()+1,'10:00')), try_book(hari()+1,'20:00')||'/'||try_book(hari()+1,'10:00');

-- 3. Batas tanggal: sebelum, sama, sesudah
select reset(); select set_sesi('malam', false, hari()+5, 'Libur');
insert into hasil select 3,'sampai=D: D-1 ditolak, D ditolak, D+1 bisa; siang bebas',
  ditolak(try_book(hari()+4,'20:00')) and ditolak(try_book(hari()+5,'20:00')) and ok(try_book(hari()+6,'20:00')) and ok(try_book(hari()+5,'10:00')),
  try_book(hari()+4,'20:00')||' | '||try_book(hari()+5,'20:00')||' | '||try_book(hari()+6,'20:00')||' | '||try_book(hari()+5,'10:00');

-- 4. sampai kosong: semua tanggal ditolak
select reset(); select set_sesi('malam', false);
insert into hasil select 4,'sampai kosong: hari ini dan +120 hari ditolak', ditolak(try_book(hari(),'20:00')) and ditolak(try_book(hari()+120,'20:00')), try_book(hari(),'20:00');

-- 5. Admin buka kembali
select set_sesi('malam', true);
insert into hasil select 5,'Buka kembali: booking bisa lagi, batas & pesan dibersihkan', ok(try_book(hari()+1,'20:00')) and (select value from operational_settings where key='sesi_malam') = '{"buka": true, "pesan": "", "sampai": null}'::jsonb,
  (select value::text from operational_settings where key='sesi_malam');

-- 6 & 7. Booking lama: MENUNGGU tetap bisa diterima, DITERIMA tidak berubah, bentrok tetap aktif
select reset();
insert into bookings(id,customer_id,nama_pelanggan,wa_pelanggan,service_id,jumlah_orang,tanggal,jam_mulai,durasi_menit,tipe_lokasi,service_price,travel_fee,status) values
 ('b0000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','A','1','90m',1,hari()+10,'19:00',90,'DI_TEMPAT',90000,0,'MENUNGGU'),
 ('b0000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','B','1','90m',1,hari()+10,'19:30',90,'DI_TEMPAT',90000,0,'MENUNGGU'),
 ('b0000000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','C','1','90m',1,hari()+11,'20:00',90,'DI_TEMPAT',90000,0,'DITERIMA');
create temp table snap as select md5(string_agg(b::text, '|' order by id)) h from bookings b where id='b0000000-0000-0000-0000-000000000003';
select set_sesi('malam', false, hari()+20);
create function acc(p uuid) returns text language plpgsql as $$
declare r jsonb; begin perform set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',false);
  r := public.accept_booking(p);
  return case when (r->>'success')::boolean then 'OK' else 'TIDAK:'||coalesce(r->>'reason','?') end; exception when others then return sqlerrm; end $$;
create temp table r6 as select acc('b0000000-0000-0000-0000-000000000001') e1;
create temp table r6b as select acc('b0000000-0000-0000-0000-000000000002') e2;
insert into hasil select 6,'Sesi tutup: MENUNGGU tetap bisa DITERIMA; bentrok tetap aktif',
  r6.e1='OK' and r6b.e2<>'OK'
  and (select status from bookings where id='b0000000-0000-0000-0000-000000000001')='DITERIMA'
  and (select status from bookings where id='b0000000-0000-0000-0000-000000000002')='MENUNGGU',
  'acc1='||(select status from bookings where id='b0000000-0000-0000-0000-000000000001')||' acc2='||(select status from bookings where id='b0000000-0000-0000-0000-000000000002')||' err2='||r6b.e2
from r6, r6b;
select set_sesi('malam', true);
insert into hasil select 7,'DITERIMA lama tidak berubah setelah tutup lalu buka', (select md5(string_agg(b::text,'|' order by id)) from bookings b where id='b0000000-0000-0000-0000-000000000003')=(select h from snap), 'hash sama';

-- 8. Fail-open
select reset(); delete from operational_settings where key='sesi_malam';
create temp table fo(k text, t text);
insert into fo select 'baris hilang', try_book(hari()+1,'20:00');
insert into operational_settings(key,value) values ('sesi_malam','"rusak"');           insert into fo select 'value string', try_book(hari()+1,'20:00');
update operational_settings set value='[1,2]' where key='sesi_malam';                  insert into fo select 'value array', try_book(hari()+1,'20:00');
update operational_settings set value='{"buka":"false"}' where key='sesi_malam';       insert into fo select 'buka string', try_book(hari()+1,'20:00');
update operational_settings set value='{"buka":false,"sampai":"bukan-tanggal"}' where key='sesi_malam'; insert into fo select 'sampai tidak valid', try_book(hari()+1,'20:00');
update operational_settings set value='{}' where key='sesi_malam';                     insert into fo select 'objek kosong', try_book(hari()+1,'20:00');
insert into hasil select 8,'Konfigurasi hilang/rusak: fail-open (sesi dianggap buka)', (select bool_and(t='OK') from fo), (select string_agg(k||'='||t, '; ') from fo);

-- 9 & 10. Hak akses
select reset();
create function gagal(q text) returns boolean language plpgsql as $$ begin execute q; return false; exception when others then return true; end $$;
set role anon;
create temp table akses as select
  gagal('select public.admin_set_sesi(''malam'',false)') a1,
  gagal('select public.admin_sesi_ringkasan()') a2,
  gagal('select public._pesan_sesi_tutup(current_date,''20:00''::time)') a3;
reset role;
insert into hasil select 9,'anon tidak bisa memanggil admin_set_sesi / ringkasan / helper', a1 and a2 and a3, a1::text||a2::text||a3::text from akses;
set role authenticated;
select set_config('request.jwt.claim.sub','cccccccc-cccc-cccc-cccc-cccccccccccc',false);
create temp table akses2 as select
  gagal('select public.admin_set_sesi(''malam'',false)') n1,
  gagal('select public.admin_sesi_ringkasan()') n2,
  gagal('select public._pesan_sesi_tutup(current_date,''20:00''::time)') n3;
reset role;
insert into hasil select 10,'authenticated non-admin ditolak (set, ringkasan, helper)', n1 and n2 and n3, n1::text||n2::text||n3::text from akses2;
select reset();
select set_config('request.jwt.claim.sub','',false);
insert into hasil select 10,'Tanpa login (uid null) ditolak admin_set_sesi', set_sesi('malam',false) is not null and (select value->>'buka' from operational_settings where key='sesi_malam')='true', 'uid kosong';

-- 11. Admin sah menutup dan membuka tiap sesi
select reset();
select set_sesi('pagi', false, hari()+3, 'Pesan uji'); 
create temp table a11 as select (select value from operational_settings where key='sesi_pagi') p, (select value from operational_settings where key='sesi_malam') m;
select set_sesi('pagi', true); select set_sesi('malam', false);
create temp table b11 as select (select value from operational_settings where key='sesi_pagi') p, (select value from operational_settings where key='sesi_malam') m;
select set_sesi('malam', true);
insert into hasil select 11,'Admin menutup/membuka pagi dan malam terpisah',
  (a11.p->>'buka')='false' and (a11.p->>'pesan')='Pesan uji' and (a11.m->>'buka')='true'
  and (b11.p->>'buka')='true' and (b11.m->>'buka')='false'
  and (select value->>'buka' from operational_settings where key='sesi_malam')='true', a11.p::text
from a11, b11;
create temp table v11 as select set_sesi('siang',false) a, set_sesi('pagi',false,hari()-1) b, set_sesi('pagi',false,hari()+400) c;
create temp table v11b as select set_sesi('pagi',false,null,repeat('x',500)) d;
insert into hasil select 11,'Validasi input: sesi salah, sampai lampau, sampai >365 hari, pesan dipotong 200',
  v11.a<>'OK' and v11.b<>'OK' and v11.c<>'OK' and v11b.d='OK'
  and length((select value->>'pesan' from operational_settings where key='sesi_pagi'))=200,
  v11.a||' | '||v11.b||' | '||v11.c
from v11, v11b;
select reset();

-- 12. Zona waktu & batas sesi
select reset(); select set_sesi('malam', false, hari());
create temp table z as select
  public._pesan_sesi_tutup(hari(),'16:30') is null as siang_1630_bebas,
  public._pesan_sesi_tutup(hari(),'17:00') is not null as malam_1700_tutup,
  public._pesan_sesi_tutup(hari(),'22:30') is not null as malam_2230_tutup,
  public._pesan_sesi_tutup(hari()+1,'22:30') is null as besok_bebas,
  try_book(hari()+1,'22:30') = 'OK' as slot_akhir_malam_ok;
insert into hasil select 12,'Batas 17:00 dan slot 22:30-24:00 benar', siang_1630_bebas and malam_1700_tutup and malam_2230_tutup and besok_bebas and slot_akhir_malam_ok, z::text from z;
set time zone 'UTC'; select set_sesi('malam', false, hari());
create temp table z2 as select ditolak(try_book(hari(),'20:00')) a, ok(try_book(hari()+1,'20:00')) b;
set time zone 'Pacific/Auckland'; select set_sesi('malam', false, hari());
create temp table z3 as select ditolak(try_book(hari(),'20:00')) a, ok(try_book(hari()+1,'20:00')) b;
reset time zone;
insert into hasil select 12,'Tanggal memakai WIB (sesi DB UTC & Auckland)', z2.a and z2.b and z3.a and z3.b, z2::text||z3::text from z2,z3;
select reset();

-- Regresi: validasi lama tetap jalan saat sesi tutup
select set_sesi('malam', false);
insert into hasil select 14,'Regresi: jam salah tetap pesan lama (bukan pesan sesi)', try_book(hari()+1,'20:15') ilike 'Jam di luar jam operasional%' and try_book(hari()+1,'14:30') ilike 'Jam di luar jam operasional%', try_book(hari()+1,'20:15');
select reset();

\echo ===== LAPORAN =====
select no, case when lulus then 'PASS' else 'FAIL' end hasil, nama, left(coalesce(bukti,''),110) bukti from hasil order by no, nama;
select count(*) filter (where not lulus) as gagal, count(*) as total from hasil;
