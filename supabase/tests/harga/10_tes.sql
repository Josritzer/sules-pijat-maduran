\set ON_ERROR_STOP off
-- Tes Harga Bertingkat & Promo. Jalankan setelah 00_base (sesi) + 05_stub_tambahan + migrasi paket5, slot, sesi, harga.
create table hasil(no int, nama text, lulus boolean, bukti text);
create function chk(n int, t text, c boolean, b text) returns void language sql as $$ insert into hasil values (n,t,coalesce(c,false),b) $$;
create function hari() returns date language sql as $$ select timezone('Asia/Jakarta', now())::date $$;
insert into admins values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
create function as_admin() returns void language sql as $$ select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',false) $$;
create function as_cust() returns void language sql as $$ select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',false) $$;
-- paket: 1..5 -> (service, tipe, orang)
create function pk(n int, out s text, out t tipe_lokasi, out o smallint) language sql as $$
  select (array['90m','120m','90m','120m','90m'])[n], (array['DI_TEMPAT','DI_TEMPAT','HOME_SERVICE','HOME_SERVICE','HOME_SERVICE'])[n]::tipe_lokasi, (array[1,1,1,1,2])[n]::smallint $$;
create function pid(n int) returns text language sql as $$ select (array['sules-90m-1','sules-120m-1','home-90m-1','home-120m-1','home-90m-2'])[n] $$;
create function cfg(n int, lvl int, tp text default null, nl numeric default null, m date default null, a date default null) returns text language plpgsql as $$
begin perform as_admin(); perform public.admin_set_harga_paket(pid(n), lvl, tp, nl, m, a); return 'OK';
exception when others then return sqlerrm; end $$;
create function reset() returns void language sql as $$
  update operational_settings set value='{"level":0,"promo":{"tipe":null,"nilai":null,"mulai":null,"akhir":null}}' where key like 'harga_paket_%' $$;
create function q(n int, jarak numeric default null) returns jsonb language plpgsql as $$
declare r record; begin select * into r from pk(n); return public.hitung_harga_booking(r.s, r.t, r.o, jarak); end $$;
create function book(n int, jarak numeric default null) returns jsonb language plpgsql as $$
declare r record; begin select * into r from pk(n);
  return public.create_booking_server('11111111-1111-1111-1111-111111111111','Uji','081', r.s, r.o, hari()+1, '10:00', r.t,
     case when r.t='HOME_SERVICE' then 'Jl Uji' end, case when r.t='HOME_SERVICE' then -7.0::float8 end, case when r.t='HOME_SERVICE' then 112.28::float8 end, jarak);
exception when others then return jsonb_build_object('error', sqlerrm); end $$;

-- 1. 5 paket x Level 0..5, tanpa promo, tanpa travel (harga dasar + level x kenaikan; Level 5 = angka Bos)
select reset();
do $$ declare n int; l int; base numeric[] := array[60000,80000,60000,80000,120000]; stp numeric[] := array[10000,10000,10000,10000,20000]; bad text := ''; cnt int := 0; r jsonb;
begin
  for n in 1..5 loop for l in 0..5 loop
    perform cfg(n,l); r := q(n, case when n>=3 then 0 end); cnt := cnt+1;
    if (r->>'harga_level')::numeric <> base[n]+l*stp[n] or (r->>'total')::numeric <> base[n]+l*stp[n] or (r->>'diskon')::numeric <> 0 or (r->>'level')::int <> l
      then bad := bad || n||'/'||l||'='||(r->>'total')||' '; end if;
  end loop; end loop;
  perform chk(1,'5 paket x 6 posisi (Dasar+Level1..5), tanpa promo: harga=dasar+level*kenaikan', bad='', 'kombinasi='||cnt||' salah=['||bad||']');
end $$;
select reset();
do $$ declare n int; v text := ''; e numeric[] := array[110000,130000,110000,130000,220000];
begin for n in 1..5 loop perform cfg(n,5); v := v || (q(n, case when n>=3 then 0 end)->>'harga_level') || ','; end loop;
  perform chk(1,'Level 5 = 110k/130k/110k/130k/220k (sesuai prompt)', v='110000,130000,110000,130000,220000,', v); end $$;
select reset();
select chk(1,'Dasar (level 0) = 60k/80k/60k/80k/120k', (select string_agg(q(n, case when n>=3 then 0 end)->>'harga_level', ',' order by n) from generate_series(1,5) n)='60000,80000,60000,80000,120000', 'ok');
select chk(1,'Level tidak bertumpuk: ganti 5->2 harga = dasar+2*kenaikan', (select cfg(1,5)='OK' and cfg(1,2)='OK' and (q(1)->>'harga_level')::numeric=80000 and cfg(5,5)='OK' and cfg(5,2)='OK' and (q(5,0)->>'harga_level')::numeric=160000), 'p1 L2=80000, p5 L2=160000');

-- 2. Biaya perjalanan (dibulatkan) & paket 5 travel satu kali
select reset();
select chk(2,'Travel: jarak<=1000 m gratis; 1001 m=Rp4 (3,5 dibulatkan); 6033 m=Rp17.616',
  (q(3,1000)->>'travel_fee')::numeric=0 and (q(3,1001)->>'travel_fee')::numeric=4 and (q(3,6033)->>'travel_fee')::numeric=17616, (q(3,1000)->>'travel_fee')||'/'||(q(3,1001)->>'travel_fee')||'/'||(q(3,6033)->>'travel_fee'));
select chk(2,'Paket 5 (2 orang): travel SATU kali (tidak dikali 2)', (q(5,6033)->>'travel_fee')::numeric=17616 and (q(5,6033)->>'total')::numeric=137616, q(5,6033)::text);
select chk(2,'Di Sules: jarak diabaikan, travel 0', (q(1,9999)->>'travel_fee')::numeric=0, 'ok');

-- 3. Promo persen 5..30 pada subtotal (harga + travel). p3 L0 jarak 6033: subtotal 77616
select reset();
do $$ declare p int; bad text := ''; r jsonb; exp numeric;
begin
  foreach p in array array[5,10,15,20,25,30] loop
    perform cfg(3,0,'PERSEN',p,hari(),hari()+5); r := q(3,6033); exp := round(77616*p/100.0);
    if (r->>'diskon')::numeric<>exp or (r->>'total')::numeric<>77616-exp or (r->>'subtotal')::numeric<>77616 then bad := bad||p||'%='||(r->>'diskon')||' '; end if;
  end loop;
  perform chk(3,'Promo persen 5/10/15/20/25/30% dihitung dari subtotal (harga+travel)', bad='', 'subtotal=77616 salah=['||bad||']');
end $$;
select chk(3,'Contoh 15%: diskon 11.642 (77.616*15%=11.642,4 dibulatkan), total 65.974', (select cfg(3,0,'PERSEN',15,hari(),hari()+5))='OK' and (q(3,6033)->>'diskon')::numeric=11642 and (q(3,6033)->>'total')::numeric=65974, q(3,6033)::text);
-- 4. Promo nominal & batas
select reset();
select chk(4,'Promo nominal Rp5.000 dari subtotal', cfg(1,0,'NOMINAL',5000,hari(),hari()+1)='OK' and (q(1)->>'diskon')::numeric=5000 and (q(1)->>'total')::numeric=55000, q(1)::text);
select chk(4,'Nominal melebihi subtotal dibatasi: diskon=subtotal, total=0 (tidak negatif)', cfg(1,0,'NOMINAL',1000000,hari(),hari()+1)='OK' and (q(1)->>'diskon')::numeric=60000 and (q(1)->>'total')::numeric=0, q(1)::text);
select chk(4,'Travel tidak digratiskan promo: nominal hanya mengurangi total, travel_fee tetap', cfg(3,0,'NOMINAL',10000,hari(),hari()+1)='OK' and (q(3,6033)->>'travel_fee')::numeric=17616 and (q(3,6033)->>'total')::numeric=67616, q(3,6033)::text);
-- 5. Masa berlaku (inklusif, WIB)
select reset(); select cfg(1,0,'PERSEN',10,hari(),hari()+2);
select chk(5,'Promo: sebelum mulai nonaktif, hari mulai aktif, hari akhir aktif, sesudah akhir nonaktif',
  not (public._hitung_harga('90m','DI_TEMPAT',1::smallint,0,hari()-1)->>'promo_aktif')::boolean
  and (public._hitung_harga('90m','DI_TEMPAT',1::smallint,0,hari())->>'promo_aktif')::boolean
  and (public._hitung_harga('90m','DI_TEMPAT',1::smallint,0,hari()+2)->>'promo_aktif')::boolean
  and not (public._hitung_harga('90m','DI_TEMPAT',1::smallint,0,hari()+3)->>'promo_aktif')::boolean, 'mulai=hari() akhir=hari()+2');
select reset(); select cfg(1,0,'PERSEN',10,hari()-10,hari()-1);
create temp table b5 as select (book(1)->>'booking_id')::uuid id;
select chk(5,'Promo kedaluwarsa: total = harga penuh, snapshot tanpa promo', (q(1)->>'promo_aktif')::boolean=false and (q(1)->>'total')::numeric=60000 and (select promo_tipe is null and diskon=0 and grand_total=60000 from bookings where id=(select id from b5)), q(1)::text);
select reset(); select cfg(1,0,'PERSEN',10,hari()+3,hari()+6);
select chk(5,'Promo belum mulai: tidak berlaku', (q(1)->>'total')::numeric=60000, q(1)::text);
-- 6. Validasi admin
select reset();
select chk(6,'Persen selain 5-30 ditolak (7, 35, 0)', cfg(1,0,'PERSEN',7,hari(),hari())<>'OK' and cfg(1,0,'PERSEN',35,hari(),hari())<>'OK' and cfg(1,0,'PERSEN',0,hari(),hari())<>'OK', cfg(1,0,'PERSEN',7,hari(),hari()));
select chk(6,'Nominal 0/negatif/desimal/>1jt ditolak', cfg(1,0,'NOMINAL',0,hari(),hari())<>'OK' and cfg(1,0,'NOMINAL',-5,hari(),hari())<>'OK' and cfg(1,0,'NOMINAL',500.5,hari(),hari())<>'OK' and cfg(1,0,'NOMINAL',1000001,hari(),hari())<>'OK', 'ok');
create function try_admin(n int, lvl int, tp text, nl numeric, m date, a date) returns text language sql as $$ select cfg(n,lvl,tp,nl,m,a) $$;
select chk(6,'Level 6 / -1 ditolak', cfg(1,6)<>'OK' and cfg(1,-1)<>'OK', cfg(1,6));
select chk(6,'Tanggal akhir < mulai ditolak; promo tanpa tanggal ditolak', cfg(1,0,'PERSEN',10,hari()+2,hari())<>'OK' and cfg(1,0,'PERSEN',10,null,null)<>'OK', cfg(1,0,'PERSEN',10,hari()+2,hari()));
do $$ declare t text; begin perform as_admin();
  begin perform public.admin_set_harga_paket('paket-ngawur',0); t:='BERHASIL(SALAH)'; exception when others then t:=sqlerrm; end;
  perform chk(6,'Paket tidak dikenal ditolak', t ilike '%Paket tidak valid%', t); end $$;
select chk(6,'Promo "TANPA" menghapus promo', cfg(1,0,'PERSEN',10,hari(),hari())='OK' and cfg(1,0,'TANPA')='OK' and (q(1)->>'diskon')::numeric=0, 'ok');
-- 7. Hak akses
do $$ declare t text; begin
  perform as_cust();
  begin perform public.admin_set_harga_paket('sules-90m-1',3); t := 'BERHASIL(SALAH)'; exception when others then t := sqlerrm; end;
  perform chk(7,'authenticated non-admin ditolak mengubah harga', t ilike '%Admin%', t);
  perform set_config('request.jwt.claim.sub','',false);
  begin perform public.admin_set_harga_paket('sules-90m-1',3); t := 'BERHASIL(SALAH)'; exception when others then t := sqlerrm; end;
  perform chk(7,'tanpa login ditolak mengubah harga', t ilike '%Admin%', t);
end $$;
select chk(7,'ACL: anon TIDAK bisa eksekusi admin_set_harga_paket/_hitung_harga/create_booking_server; anon BISA hitung_harga_booking & harga_paket_aktif',
  not has_function_privilege('anon','public.admin_set_harga_paket(text,integer,text,numeric,date,date)','execute')
  and not has_function_privilege('anon','public._hitung_harga(text,tipe_lokasi,smallint,numeric,date)','execute')
  and not has_function_privilege('authenticated','public._hitung_harga(text,tipe_lokasi,smallint,numeric,date)','execute')
  and has_function_privilege('authenticated','public.admin_set_harga_paket(text,integer,text,numeric,date,date)','execute')
  and has_function_privilege('anon','public.hitung_harga_booking(text,tipe_lokasi,smallint,numeric)','execute')
  and has_function_privilege('anon','public.harga_paket_aktif()','execute')
  and not has_function_privilege('anon','public.list_bookings_admin(booking_status)','execute'), 'acl');

-- 8. Booking baru: snapshot lengkap & generated grand_total
select reset(); select cfg(3,2,'PERSEN',10,hari(),hari()+3);
create temp table b8 as select (book(3,6033)->>'booking_id')::uuid id;
select chk(8,'create_booking_server menyimpan snapshot: dasar, level, travel, promo, diskon, subtotal, total',
  (select (b.harga_dasar=60000 and b.level_harga=2 and b.service_price=80000 and b.travel_fee=17616 and b.subtotal=97616 and b.promo_tipe='PERSEN' and b.promo_nilai=10 and b.diskon=9762 and b.grand_total=87854 and b.promo_akhir=hari()+3)
    from bookings b where b.id=(select id from b8)), (select row_to_json(b)::text from bookings b where b.id=(select id from b8)));
select chk(8,'Respons RPC = baris tersimpan = quote publik', (select book(3,6033)->>'grand_total')::numeric = (q(3,6033)->>'total')::numeric, q(3,6033)::text);
select chk(8,'Paket 5 end-to-end (L1, nominal 20k, jarak 3000): 140k+7k-20k=127k', cfg(5,1,'NOMINAL',20000,hari(),hari()+1)='OK' and (book(5,3000)->>'grand_total')::numeric=127000, (book(5,3000))::text);
-- 9. Snapshot tidak berubah saat konfigurasi diganti
select reset(); select cfg(1,3,'PERSEN',20,hari(),hari()+1);
create temp table snap as select (book(1)->>'booking_id')::uuid id;
select cfg(1,5,'NOMINAL',1000,hari(),hari()+1); select cfg(1,0);
select chk(9,'Booking lama tidak berubah setelah level/promo diganti (90k-20%=72k tetap)', (select grand_total=72000 and level_harga=3 and diskon=18000 from bookings where id=(select id from snap)), (select grand_total::text from bookings where id=(select id from snap)));
-- 10. Kompatibilitas booking lama
select chk(10,'3 booking lama: level/promo NULL, diskon 0, grand_total sama persis seperti sebelum migrasi',
  (select count(*)=3 and bool_and(diskon=0 and level_harga is null and promo_tipe is null)
     and sum(grand_total)=80332.50+120304.50+60000 from bookings where nama_pelanggan like 'Lama%'), (select sum(grand_total)::text from bookings where nama_pelanggan like 'Lama%'));
do $$ declare t1 text; t2 text; begin
  begin update bookings set diskon = 999999 where nama_pelanggan='Lama3'; t1:='BERHASIL(SALAH)'; exception when others then t1:=sqlerrm; end;
  begin update bookings set diskon = -1 where nama_pelanggan='Lama3'; t2:='BERHASIL(SALAH)'; exception when others then t2:=sqlerrm; end;
  perform chk(10,'Constraint tabel: diskon > subtotal & diskon negatif ditolak', t1 ilike '%bookings_diskon_max_check%' and t2 ilike '%bookings_diskon_check%', t1||' | '||t2); end $$;
-- 11. Konfigurasi rusak -> fail-safe ke Dasar
select reset();
update operational_settings set value='"rusak"' where key='harga_paket_sules-90m-1';
update operational_settings set value='{"level":9,"promo":{"tipe":"PERSEN","nilai":"abc","mulai":"x","akhir":"y"}}' where key='harga_paket_sules-120m-1';
delete from operational_settings where key='harga_paket_home-90m-1';
select chk(11,'Konfigurasi rusak/level 9/hilang => harga Dasar tanpa promo (tidak error)', (q(1)->>'total')::numeric=60000 and (q(2)->>'total')::numeric=80000 and (q(3,0)->>'total')::numeric=60000, (q(1)->>'total')||'/'||(q(2)->>'total')||'/'||(q(3,0)->>'total'));
select reset();
-- 12. create_booking (RPC lama) selaras dengan create_booking_server
select cfg(4,4,'PERSEN',10,hari(),hari()+2);
do $$ declare a jsonb; b jsonb; begin
  perform as_cust();
  a := public.create_booking('Uji','081','120m',1::smallint,hari()+1,'10:00','HOME_SERVICE','Jl',-7::float8,112.28::float8,6033);
  b := book(4,6033);
  perform chk(12,'create_booking (lama) = create_booking_server untuk input sama (harga level4 + travel + promo)',
    (a->>'grand_total')::numeric=(b->>'grand_total')::numeric and (a->>'diskon')::numeric=(b->>'diskon')::numeric and (a->>'grand_total')::numeric=(select round((120000+17616)*0.9)),
    a::text||' | '||b::text);
end $$;
-- 13. Katalog publik & daftar admin
select reset(); select cfg(2,3,'PERSEN',25,hari(),hari()+9); select cfg(1,1,'PERSEN',10,hari()+5,hari()+9);
select set_config('request.jwt.claim.sub','',false);
select chk(13,'harga_paket_aktif (publik): 5 baris; promo belum mulai tidak bocor; promo aktif tampil',
  (select jsonb_array_length(public.harga_paket_aktif())=5 and (public.harga_paket_aktif()->0->>'promo_aktif')='false' and (public.harga_paket_aktif()->0->'promo_konfigurasi') = 'null'::jsonb and (public.harga_paket_aktif()->1->>'promo_aktif')='true' and (public.harga_paket_aktif()->1->>'harga_level')='110000'), left(public.harga_paket_aktif()::text,300));
select as_admin();
select chk(13,'harga_paket_aktif (admin): konfigurasi promo mentah tampil, termasuk yang belum mulai', (public.harga_paket_aktif()->0->'promo_konfigurasi'->>'tipe')='PERSEN', 'ok');
select chk(13,'list_bookings_admin & _period mengembalikan kolom baru; booking lama diskon=0',
  (select count(*)>=3 and bool_and(diskon is not null) and bool_and(subtotal=grand_total+diskon) from public.list_bookings_admin())
  and (select count(*)>=3 from public.list_bookings_admin_period('2026-01-01','2030-01-01')), (select count(*)::text from public.list_bookings_admin()));
-- 14. Pembulatan: nilai pecahan setengah dibulatkan ke atas
select reset(); select cfg(3,0,'PERSEN',5,hari(),hari()+1);
select chk(14,'Pembulatan half-up: travel 10,5 -> 11; diskon 60.011 x 5% = 3.000,55 -> 3.001',
  (q(3,1003)->>'travel_fee')::numeric=11 and (q(3,1003)->>'diskon')::numeric=round(60011*0.05) , q(3,1003)::text);
select reset();
select no, nama, case when lulus then 'PASS' else 'FAIL' end hasil, bukti from hasil order by no, nama;
