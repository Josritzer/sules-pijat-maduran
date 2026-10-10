\set ON_ERROR_STOP off
create table if not exists t.h2(nama text, harapan text, hasil text);
-- data buatan: satu tanggal dengan semua status
insert into bookings(tanggal,jam_mulai,durasi_menit,status,customer_id) values
 ('2027-06-01','10:00',90,'DITERIMA',gen_random_uuid()),
 ('2027-06-01','22:30',90,'DITERIMA',gen_random_uuid()),
 ('2027-06-01','08:00',90,'MENUNGGU',gen_random_uuid()),
 ('2027-06-01','12:00',90,'DITOLAK',gen_random_uuid()),
 ('2027-06-01','13:00',90,'DIBATALKAN',gen_random_uuid()),
 ('2027-06-01','19:00',90,'SELESAI',gen_random_uuid()),
 ('2027-06-02','10:00',90,'DITERIMA',gen_random_uuid());
grant select on t.h2 to public;
select set_config('request.jwt.claim.sub','bbbbbbbb-0000-0000-0000-000000000002',false);
set role authenticated;
select 'A1 authenticated, tgl 06-01 hanya DITERIMA' as uji, string_agg(mulai_menit||'-'||selesai_menit, ',' order by mulai_menit) as hasil, '600-690,1350-1440' as harapan from public.get_slot_terisi('2027-06-01');
select 'A2 tanggal lain tidak bocor' as uji, string_agg(mulai_menit||'-'||selesai_menit, ',') as hasil, '600-690' as harapan from public.get_slot_terisi('2027-06-02');
select 'A3 tanggal kosong' as uji, count(*)::text as hasil, '0' as harapan from public.get_slot_terisi('2030-01-01');
select 'A4 tanggal NULL' as uji, count(*)::text as hasil, '0' as harapan from public.get_slot_terisi(null);
select 'A5 jumlah & tipe kolom' as uji, string_agg(a||':'||b, ',') as hasil, 'mulai_menit:int4,selesai_menit:int4' as harapan from (select a.attname a, format_type(a.atttypid,a.atttypmod) b from pg_attribute a join pg_proc p on p.proargnames is not null where false) z;
reset role;
select set_config('request.jwt.claim.sub','',false);
set role authenticated;
select 'A6 authenticated tanpa uid -> kosong' as uji, count(*)::text as hasil, '0' as harapan from public.get_slot_terisi('2027-06-01');
reset role;
set role anon;
select 'A7 anon' as uji, count(*)::text as hasil, 'ERROR permission denied' as harapan from public.get_slot_terisi('2027-06-01');
reset role;
select 'A8 anon baca tabel bookings langsung (tanpa RLS di harness; hanya cek fungsi tidak memberi hak)' as uji, 'dilewati' as hasil, '-' as harapan;
