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
-- create_booking lama (definisi produksi, disalin dari pg_get_functiondef)
CREATE OR REPLACE FUNCTION public.create_booking(p_nama text, p_wa text, p_service_id text, p_jumlah_orang smallint, p_tanggal date, p_jam_mulai time without time zone, p_tipe_lokasi tipe_lokasi, p_alamat text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_jarak_meter numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_service services%rowtype;
  v_customer_id uuid;
  v_gratis_meter numeric;
  v_tarif numeric;
  v_service_price numeric;
  v_travel_fee numeric;
  v_booking bookings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Anda harus login (verifikasi email) terlebih dahulu sebelum membuat booking' using errcode='28000';
  end if;
  if p_nama is null or btrim(p_nama)='' then raise exception 'Nama pelanggan wajib diisi'; end if;
  if p_wa is null or btrim(p_wa)='' then raise exception 'Nomor WA wajib diisi'; end if;
  if p_jumlah_orang < 1 or p_jumlah_orang > 2 then raise exception 'Jumlah orang harus 1 atau 2'; end if;

  select * into v_service from services where id=p_service_id and aktif=true;
  if not found then raise exception 'Layanan tidak ditemukan: %', p_service_id; end if;

  if p_jumlah_orang = 2
     and not (p_tipe_lokasi = 'HOME_SERVICE' and p_service_id = '90m') then
    raise exception 'Paket 2 orang hanya tersedia untuk Pijat 90 Menit ke Rumah';
  end if;

  if not _dalam_jam_operasional(p_jam_mulai,v_service.durasi_menit) then
    raise exception 'Jam di luar jam operasional atau melewati jam tutup';
  end if;
  if p_tipe_lokasi='HOME_SERVICE' and (p_lat is null or p_lng is null) then
    raise exception 'Home Service wajib menyertakan lokasi (lat/lng)';
  end if;

  insert into customers(id,nama,wa) values(auth.uid(),btrim(p_nama),btrim(p_wa))
  on conflict(id) do update set nama=excluded.nama,wa=excluded.wa returning id into v_customer_id;

  if p_tipe_lokasi='HOME_SERVICE' and p_service_id='90m' and p_jumlah_orang=2 then
    v_service_price := 120000;
  else
    v_service_price := v_service.harga * p_jumlah_orang;
  end if;

  select (value)::numeric into v_gratis_meter from operational_settings where key='travel_gratis_meter';
  select (value)::numeric into v_tarif from operational_settings where key='travel_tarif_per_meter';

  if p_tipe_lokasi='DI_TEMPAT' then
    v_travel_fee:=0;
  else
    if p_jarak_meter is null then raise exception 'Jarak tempuh wajib untuk Home Service'; end if;
    v_travel_fee:=greatest(p_jarak_meter-v_gratis_meter,0)*v_tarif;
  end if;

  insert into bookings(
    customer_id,nama_pelanggan,wa_pelanggan,service_id,jumlah_orang,tanggal,jam_mulai,durasi_menit,
    tipe_lokasi,alamat,lat,lng,jarak_meter,service_price,travel_fee,status
  ) values(
    v_customer_id,btrim(p_nama),btrim(p_wa),p_service_id,p_jumlah_orang,p_tanggal,p_jam_mulai,v_service.durasi_menit,
    p_tipe_lokasi,p_alamat,p_lat,p_lng,p_jarak_meter,v_service_price,v_travel_fee,'MENUNGGU'
  ) returning * into v_booking;

  return jsonb_build_object('booking_id',v_booking.id,'access_token',v_booking.access_token,'status',v_booking.status,
    'service_price',v_booking.service_price,'travel_fee',v_booking.travel_fee,'grand_total',v_booking.grand_total);
end;
$function$;
-- 3 booking "lama" sebelum migrasi (untuk uji kompatibilitas)
insert into customers values ('11111111-1111-1111-1111-111111111111','Uji','081') on conflict do nothing;
insert into bookings(customer_id,nama_pelanggan,wa_pelanggan,service_id,jumlah_orang,tanggal,jam_mulai,durasi_menit,tipe_lokasi,service_price,travel_fee,status)
 values ('11111111-1111-1111-1111-111111111111','Lama1','081','120m',1,'2026-09-01','10:00',120,'HOME_SERVICE',80000,332.50,'MENUNGGU'),
        ('11111111-1111-1111-1111-111111111111','Lama2','081','90m',2,'2026-09-02','19:00',180,'HOME_SERVICE',120000,304.50,'SELESAI'),
        ('11111111-1111-1111-1111-111111111111','Lama3','081','90m',1,'2026-09-03','09:00',90,'DI_TEMPAT',60000,0,'DITOLAK');
