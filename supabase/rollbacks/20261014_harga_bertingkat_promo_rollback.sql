-- Rollback: Harga bertingkat & promo (20261014_harga_bertingkat_promo.sql).
-- Mengembalikan fungsi ke definisi produksi sebelum fitur (create_booking_server versi sesi 20261013, create_booking lama,
-- list_bookings_admin / _period lama), grand_total kembali GENERATED (service_price + travel_fee), dan membuang kolom/fungsi/konfigurasi harga.
-- KEAMANAN DATA: rollback DIBATALKAN bila sudah ada booking ber-diskon (grand_total lama tidak memuat diskon, total akan salah).
-- Dalam kasus itu: JANGAN paksa; putuskan dulu bersama Admin (mis. simpan diskon ke catatan) lalu hapus guard secara sadar.
-- Dijalankan dalam satu transaksi: gagal di mana pun = tidak ada yang berubah.

BEGIN;

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM public.bookings WHERE diskon > 0) THEN
    RAISE EXCEPTION 'Rollback dibatalkan: ada booking dengan diskon. Total lama tidak memuat diskon.';
  END IF;
END
$guard$;

-- 1. Fungsi lama (sebelum kolom dibuang)
CREATE OR REPLACE FUNCTION public.create_booking_server(p_customer_id uuid, p_nama text, p_wa text, p_service_id text, p_jumlah_orang smallint, p_tanggal date, p_jam_mulai time without time zone, p_tipe_lokasi tipe_lokasi, p_alamat text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_jarak_meter numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_service public.services%rowtype;
  v_gratis_meter numeric;
  v_tarif numeric;
  v_service_price numeric;
  v_travel_fee numeric;
  v_durasi_menit integer;
  v_booking public.bookings%rowtype;
  v_sesi_tutup text;
BEGIN
  IF p_customer_id IS NULL THEN RAISE EXCEPTION 'Customer ID wajib'; END IF;
  IF p_nama IS NULL OR btrim(p_nama) = '' THEN RAISE EXCEPTION 'Nama pelanggan wajib diisi'; END IF;
  IF p_wa IS NULL OR btrim(p_wa) = '' THEN RAISE EXCEPTION 'Nomor WA wajib diisi'; END IF;
  IF p_jumlah_orang IS NULL OR p_jumlah_orang < 1 OR p_jumlah_orang > 2 THEN RAISE EXCEPTION 'Jumlah orang harus 1 atau 2'; END IF;
  IF p_tanggal IS NULL OR p_tanggal < timezone('Asia/Jakarta', now())::date THEN RAISE EXCEPTION 'Tanggal booking tidak valid atau sudah lewat'; END IF;
  IF p_jam_mulai IS NULL THEN RAISE EXCEPTION 'Jam booking wajib diisi'; END IF;
  IF p_tipe_lokasi IS NULL THEN RAISE EXCEPTION 'Lokasi layanan wajib dipilih'; END IF;

  IF NOT (
    (p_service_id = '90m' AND p_tipe_lokasi = 'DI_TEMPAT' AND p_jumlah_orang = 1) OR
    (p_service_id = '120m' AND p_tipe_lokasi = 'DI_TEMPAT' AND p_jumlah_orang = 1) OR
    (p_service_id = '90m' AND p_tipe_lokasi = 'HOME_SERVICE' AND p_jumlah_orang = 1) OR
    (p_service_id = '120m' AND p_tipe_lokasi = 'HOME_SERVICE' AND p_jumlah_orang = 1) OR
    (p_service_id = '90m' AND p_tipe_lokasi = 'HOME_SERVICE' AND p_jumlah_orang = 2)
  ) THEN RAISE EXCEPTION 'Paket yang dipilih tidak valid'; END IF;

  SELECT * INTO v_service FROM public.services WHERE id = p_service_id AND aktif = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Layanan tidak ditemukan'; END IF;

  v_durasi_menit := CASE
    WHEN p_tipe_lokasi = 'HOME_SERVICE' AND p_service_id = '90m' AND p_jumlah_orang = 2 THEN 180
    ELSE v_service.durasi_menit
  END;

  IF NOT public._dalam_jam_operasional(p_jam_mulai, v_durasi_menit) THEN
    RAISE EXCEPTION 'Jam di luar jam operasional atau melewati jam tutup';
  END IF;

  -- Sesi ditutup Admin (siang < 17:00, malam >= 17:00). Hanya booking BARU; fail-open bila konfigurasi rusak.
  v_sesi_tutup := public._pesan_sesi_tutup(p_tanggal, p_jam_mulai);
  IF v_sesi_tutup IS NOT NULL THEN
    RAISE EXCEPTION '%', v_sesi_tutup;
  END IF;

  IF p_tipe_lokasi = 'HOME_SERVICE' THEN
    IF p_lat IS NULL OR p_lng IS NULL OR p_lat::text = 'NaN' OR p_lng::text = 'NaN' OR
       p_lat < -90 OR p_lat > 90 OR p_lng < -180 OR p_lng > 180 THEN
      RAISE EXCEPTION 'Home Service wajib menyertakan lokasi valid (lat/lng)';
    END IF;
    IF p_jarak_meter IS NULL OR p_jarak_meter < 0 OR p_jarak_meter::text IN ('NaN', 'Infinity', '-Infinity') THEN
      RAISE EXCEPTION 'Jarak tempuh Google Routes wajib untuk Home Service';
    END IF;
  END IF;

  IF p_tipe_lokasi = 'HOME_SERVICE' AND p_service_id = '90m' AND p_jumlah_orang = 2 THEN
    v_service_price := 120000;
  ELSE
    v_service_price := v_service.harga * p_jumlah_orang;
  END IF;

  SELECT value::numeric INTO v_gratis_meter FROM public.operational_settings WHERE key = 'travel_gratis_meter';
  SELECT value::numeric INTO v_tarif FROM public.operational_settings WHERE key = 'travel_tarif_per_meter';
  IF v_gratis_meter IS NULL OR v_tarif IS NULL THEN RAISE EXCEPTION 'Aturan travel fee belum tersedia'; END IF;

  IF p_tipe_lokasi = 'DI_TEMPAT' THEN
    v_travel_fee := 0;
  ELSE
    v_travel_fee := greatest(p_jarak_meter - v_gratis_meter, 0) * v_tarif;
  END IF;

  INSERT INTO public.customers (id, nama, wa)
  VALUES (p_customer_id, btrim(p_nama), btrim(p_wa))
  ON CONFLICT (id) DO UPDATE SET nama = excluded.nama, wa = excluded.wa;

  INSERT INTO public.bookings (
    customer_id, nama_pelanggan, wa_pelanggan, service_id, jumlah_orang, tanggal, jam_mulai,
    durasi_menit, tipe_lokasi, alamat, lat, lng, jarak_meter, service_price, travel_fee, status
  ) VALUES (
    p_customer_id, btrim(p_nama), btrim(p_wa), p_service_id, p_jumlah_orang, p_tanggal, p_jam_mulai,
    v_durasi_menit, p_tipe_lokasi, p_alamat, p_lat, p_lng,
    CASE WHEN p_tipe_lokasi = 'HOME_SERVICE' THEN p_jarak_meter ELSE NULL END,
    v_service_price, v_travel_fee, 'MENUNGGU'
  ) RETURNING * INTO v_booking;

  RETURN jsonb_build_object(
    'booking_id', v_booking.id, 'access_token', v_booking.access_token, 'status', v_booking.status,
    'service_price', v_booking.service_price, 'travel_fee', v_booking.travel_fee, 'grand_total', v_booking.grand_total
  );
END;
$function$;

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


REVOKE ALL ON FUNCTION public.create_booking_server(uuid, text, text, text, smallint, date, time without time zone, tipe_lokasi, text, double precision, double precision, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_booking(text, text, text, smallint, date, time without time zone, tipe_lokasi, text, double precision, double precision, numeric) FROM PUBLIC, anon, authenticated;

-- 2. Daftar booking Admin: kembali ke kolom lama (tipe kembalian berbeda => DROP + CREATE), hak akses seperti produksi.
DROP FUNCTION public.list_bookings_admin(booking_status);
DROP FUNCTION public.list_bookings_admin_period(date, date, booking_status);
CREATE FUNCTION public.list_bookings_admin(p_status booking_status DEFAULT NULL::booking_status)
 RETURNS TABLE(id uuid, nama text, wa text, service_id text, jumlah_orang smallint, tanggal date, jam_mulai time without time zone, tipe_lokasi tipe_lokasi, alamat text, lat double precision, lng double precision, jarak_meter numeric, service_price numeric, travel_fee numeric, grand_total numeric, status booking_status, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
begin
  if not is_admin() then raise exception 'Hanya admin yang boleh melihat daftar booking'; end if;
  return query select b.id, coalesce(b.nama_pelanggan, c.nama), coalesce(b.wa_pelanggan, c.wa), b.service_id, b.jumlah_orang, b.tanggal, b.jam_mulai,
           b.tipe_lokasi, b.alamat, b.lat, b.lng, b.jarak_meter, b.service_price, b.travel_fee, b.grand_total, b.status, b.created_at
    from bookings b join customers c on c.id = b.customer_id where (p_status is null or b.status = p_status) order by b.created_at desc;
end; $function$;
CREATE FUNCTION public.list_bookings_admin_period(p_start_date date, p_end_date date, p_status booking_status DEFAULT NULL::booking_status)
 RETURNS TABLE(id uuid, nama text, wa text, service_id text, jumlah_orang smallint, tanggal date, jam_mulai time without time zone, tipe_lokasi tipe_lokasi, alamat text, lat double precision, lng double precision, jarak_meter numeric, service_price numeric, travel_fee numeric, grand_total numeric, status booking_status, created_at timestamp with time zone)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
begin
  if not is_admin() then raise exception 'Hanya admin yang boleh melihat daftar booking'; end if;
  return query select b.id, coalesce(b.nama_pelanggan, c.nama), coalesce(b.wa_pelanggan, c.wa), b.service_id, b.jumlah_orang, b.tanggal, b.jam_mulai,
           b.tipe_lokasi, b.alamat, b.lat, b.lng, b.jarak_meter, b.service_price, b.travel_fee, b.grand_total, b.status, b.created_at
    from bookings b join customers c on c.id = b.customer_id where b.tanggal between p_start_date and p_end_date and (p_status is null or b.status = p_status) order by b.created_at desc;
end; $function$;

REVOKE ALL ON FUNCTION public.list_bookings_admin(booking_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_bookings_admin(booking_status) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.list_bookings_admin_period(date, date, booking_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_bookings_admin_period(date, date, booking_status) TO authenticated, service_role;

-- 3. Fungsi baru dibuang
DROP FUNCTION public.admin_set_harga_paket(text, integer, text, numeric, date, date);
DROP FUNCTION public.harga_paket_aktif();
DROP FUNCTION public.hitung_harga_booking(text, tipe_lokasi, smallint, numeric);
DROP FUNCTION public._hitung_harga(text, tipe_lokasi, smallint, numeric, date);
DROP FUNCTION public._hitung_travel(tipe_lokasi, numeric);
DROP FUNCTION public._paket_id(text, tipe_lokasi, smallint);

-- 4. Tabel: constraint & kolom baru dibuang; grand_total kembali GENERATED seperti semula
ALTER TABLE public.bookings
  DROP CONSTRAINT bookings_promo_konsisten_check,
  DROP CONSTRAINT bookings_snapshot_level_check,
  DROP CONSTRAINT bookings_diskon_max_check,
  DROP CONSTRAINT bookings_diskon_check,
  DROP CONSTRAINT bookings_promo_tipe_check,
  DROP CONSTRAINT bookings_level_harga_check;
ALTER TABLE public.bookings DROP COLUMN grand_total, DROP COLUMN subtotal;
ALTER TABLE public.bookings
  DROP COLUMN harga_dasar, DROP COLUMN level_harga, DROP COLUMN promo_tipe, DROP COLUMN promo_nilai,
  DROP COLUMN promo_mulai, DROP COLUMN promo_akhir, DROP COLUMN diskon;
ALTER TABLE public.bookings
  ADD COLUMN grand_total numeric GENERATED ALWAYS AS (service_price + travel_fee) STORED;

-- 5. Konfigurasi harga dibuang
DELETE FROM public.operational_settings WHERE key LIKE 'harga\_paket\_%';

COMMIT;
