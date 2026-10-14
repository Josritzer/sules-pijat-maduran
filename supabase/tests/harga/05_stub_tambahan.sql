-- Tambahan stub di atas supabase/tests/sesi/00_base.sql: harga produksi + fungsi daftar admin lama (disalin dari definisi produksi).
\set ON_ERROR_STOP on
do $$ begin if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if; end $$;
update services set harga = 60000 where id='90m';
update services set harga = 80000 where id='120m';
alter table bookings add column if not exists created_at timestamptz default now();
CREATE OR REPLACE FUNCTION public.list_bookings_admin(p_status booking_status DEFAULT NULL::booking_status)
 RETURNS TABLE(id uuid, nama text, wa text, service_id text, jumlah_orang smallint, tanggal date, jam_mulai time without time zone, tipe_lokasi tipe_lokasi, alamat text, lat double precision, lng double precision, jarak_meter numeric, service_price numeric, travel_fee numeric, grand_total numeric, status booking_status, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
begin
  if not is_admin() then raise exception 'Hanya admin yang boleh melihat daftar booking'; end if;
  return query select b.id, coalesce(b.nama_pelanggan, c.nama), coalesce(b.wa_pelanggan, c.wa), b.service_id, b.jumlah_orang, b.tanggal, b.jam_mulai,
           b.tipe_lokasi, b.alamat, b.lat, b.lng, b.jarak_meter, b.service_price, b.travel_fee, b.grand_total, b.status, b.created_at
    from bookings b join customers c on c.id = b.customer_id where (p_status is null or b.status = p_status) order by b.created_at desc;
end; $f$;
CREATE OR REPLACE FUNCTION public.list_bookings_admin_period(p_start_date date, p_end_date date, p_status booking_status DEFAULT NULL::booking_status)
 RETURNS TABLE(id uuid, nama text, wa text, service_id text, jumlah_orang smallint, tanggal date, jam_mulai time without time zone, tipe_lokasi tipe_lokasi, alamat text, lat double precision, lng double precision, jarak_meter numeric, service_price numeric, travel_fee numeric, grand_total numeric, status booking_status, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
begin
  if not is_admin() then raise exception 'Hanya admin yang boleh melihat daftar booking'; end if;
  return query select b.id, coalesce(b.nama_pelanggan, c.nama), coalesce(b.wa_pelanggan, c.wa), b.service_id, b.jumlah_orang, b.tanggal, b.jam_mulai,
           b.tipe_lokasi, b.alamat, b.lat, b.lng, b.jarak_meter, b.service_price, b.travel_fee, b.grand_total, b.status, b.created_at
    from bookings b join customers c on c.id = b.customer_id where b.tanggal between p_start_date and p_end_date and (p_status is null or b.status = p_status) order by b.created_at desc;
end; $f$;
REVOKE ALL ON FUNCTION public.list_bookings_admin(booking_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_bookings_admin(booking_status) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.list_bookings_admin_period(date,date,booking_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_bookings_admin_period(date,date,booking_status) TO authenticated, service_role;
-- create_booking lama (definisi produksi) agar dapat diuji
CREATE OR REPLACE FUNCTION public.create_booking(p_nama text, p_wa text, p_service_id text, p_jumlah_orang smallint, p_tanggal date, p_jam_mulai time without time zone, p_tipe_lokasi tipe_lokasi, p_alamat text DEFAULT NULL, p_lat double precision DEFAULT NULL, p_lng double precision DEFAULT NULL, p_jarak_meter numeric DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$ begin return '{}'::jsonb; end; $f$;
-- 3 booking "lama" sebelum migrasi (untuk uji kompatibilitas)
insert into customers values ('11111111-1111-1111-1111-111111111111','Uji','081') on conflict do nothing;
insert into bookings(customer_id,nama_pelanggan,wa_pelanggan,service_id,jumlah_orang,tanggal,jam_mulai,durasi_menit,tipe_lokasi,service_price,travel_fee,status)
 values ('11111111-1111-1111-1111-111111111111','Lama1','081','120m',1,'2026-09-01','10:00',120,'HOME_SERVICE',80000,332.50,'MENUNGGU'),
        ('11111111-1111-1111-1111-111111111111','Lama2','081','90m',2,'2026-09-02','19:00',180,'HOME_SERVICE',120000,304.50,'SELESAI'),
        ('11111111-1111-1111-1111-111111111111','Lama3','081','90m',1,'2026-09-03','09:00',90,'DI_TEMPAT',60000,0,'DITOLAK');
