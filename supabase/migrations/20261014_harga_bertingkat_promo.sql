-- SL Relax V1: Harga bertingkat (Dasar + Level 1..5) & promo per paket.
-- Server = sumber kebenaran. Rollback: supabase/rollbacks/20261014_harga_bertingkat_promo_rollback.sql
--
-- Aturan:
--   harga_level = harga_dasar + level * kenaikan   (level 0 = Dasar; 1..5; TIDAK ditumpuk)
--   kenaikan    = 10.000 (paket 1-4), 20.000 (paket 5)
--   travel_fee  = round(max(jarak - gratis_meter, 0) * tarif_per_meter)   -- pembulatan rupiah penuh (half up)
--   subtotal    = harga_level + travel_fee
--   diskon      = PERSEN: round(subtotal * persen / 100) | NOMINAL: nilai ; selalu dibatasi <= subtotal
--   total akhir = subtotal - diskon (>= 0)
-- Promo aktif jika tanggal HARI INI (Asia/Jakarta, saat booking dibuat) berada di [mulai, akhir] inklusif.
-- Konfigurasi di operational_settings: harga_paket_<paket_id> = {"level":0,"promo":{"tipe":null,"nilai":null,"mulai":null,"akhir":null}}
-- Konfigurasi hilang/rusak => fail-safe ke harga Dasar tanpa promo.

BEGIN;

-- 1. Kolom snapshot di bookings (booking lama: NULL / diskon 0 -> total tetap sama).
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS harga_dasar  numeric,
  ADD COLUMN IF NOT EXISTS level_harga  smallint,
  ADD COLUMN IF NOT EXISTS promo_tipe   text,
  ADD COLUMN IF NOT EXISTS promo_nilai  numeric,
  ADD COLUMN IF NOT EXISTS promo_mulai  date,
  ADD COLUMN IF NOT EXISTS promo_akhir  date,
  ADD COLUMN IF NOT EXISTS diskon       numeric NOT NULL DEFAULT 0;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_level_harga_check CHECK (level_harga IS NULL OR level_harga BETWEEN 0 AND 5),
  ADD CONSTRAINT bookings_promo_tipe_check  CHECK (promo_tipe IS NULL OR promo_tipe IN ('PERSEN','NOMINAL')),
  ADD CONSTRAINT bookings_diskon_check      CHECK (diskon >= 0);

-- 2. grand_total (kolom GENERATED) = total akhir setelah diskon. Diganti dengan drop + add (portabel PG16/17).
--    Nilai booking lama tidak berubah (diskon = 0). subtotal ditambah sebagai kolom generated.
ALTER TABLE public.bookings DROP COLUMN grand_total;
ALTER TABLE public.bookings
  ADD COLUMN subtotal    numeric GENERATED ALWAYS AS (service_price + travel_fee) STORED,
  ADD COLUMN grand_total numeric GENERATED ALWAYS AS (service_price + travel_fee - diskon) STORED;
-- Konsistensi snapshot: diskon & level harus cocok dengan rumus server (menolak data menyimpang walau lewat SQL langsung).
-- grand_total (GENERATED) otomatis = service_price + travel_fee - diskon, sehingga total akhir tidak bisa menyimpang.
ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_diskon_max_check CHECK (diskon <= service_price + travel_fee),
  ADD CONSTRAINT bookings_snapshot_level_check CHECK (
    (harga_dasar IS NULL) = (level_harga IS NULL)
    AND (level_harga IS NULL
         OR service_price = harga_dasar + level_harga * CASE WHEN jumlah_orang = 2 THEN 20000 ELSE 10000 END)),
  ADD CONSTRAINT bookings_promo_konsisten_check CHECK (
    (promo_tipe IS NULL AND promo_nilai IS NULL AND promo_mulai IS NULL AND promo_akhir IS NULL AND diskon = 0)
    OR (promo_tipe = 'PERSEN' AND promo_nilai IN (5,10,15,20,25,30)
        AND promo_mulai IS NOT NULL AND promo_akhir IS NOT NULL AND promo_akhir >= promo_mulai
        AND diskon = least(service_price + travel_fee, round((service_price + travel_fee) * promo_nilai / 100, 0)))
    OR (promo_tipe = 'NOMINAL' AND promo_nilai > 0 AND promo_nilai = trunc(promo_nilai)
        AND promo_mulai IS NOT NULL AND promo_akhir IS NOT NULL AND promo_akhir >= promo_mulai
        AND diskon = least(service_price + travel_fee, promo_nilai)));

-- 3. Konfigurasi awal: 5 paket, level Dasar, tanpa promo.
INSERT INTO public.operational_settings (key, value) VALUES
  ('harga_paket_sules-90m-1',  '{"level":0,"promo":{"tipe":null,"nilai":null,"mulai":null,"akhir":null}}'::jsonb),
  ('harga_paket_sules-120m-1', '{"level":0,"promo":{"tipe":null,"nilai":null,"mulai":null,"akhir":null}}'::jsonb),
  ('harga_paket_home-90m-1',   '{"level":0,"promo":{"tipe":null,"nilai":null,"mulai":null,"akhir":null}}'::jsonb),
  ('harga_paket_home-120m-1',  '{"level":0,"promo":{"tipe":null,"nilai":null,"mulai":null,"akhir":null}}'::jsonb),
  ('harga_paket_home-90m-2',   '{"level":0,"promo":{"tipe":null,"nilai":null,"mulai":null,"akhir":null}}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- 4. Helper internal.
CREATE OR REPLACE FUNCTION public._paket_id(p_service_id text, p_tipe tipe_lokasi, p_orang smallint)
 RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT CASE
    WHEN p_service_id = '90m'  AND p_tipe = 'DI_TEMPAT'    AND p_orang = 1 THEN 'sules-90m-1'
    WHEN p_service_id = '120m' AND p_tipe = 'DI_TEMPAT'    AND p_orang = 1 THEN 'sules-120m-1'
    WHEN p_service_id = '90m'  AND p_tipe = 'HOME_SERVICE' AND p_orang = 1 THEN 'home-90m-1'
    WHEN p_service_id = '120m' AND p_tipe = 'HOME_SERVICE' AND p_orang = 1 THEN 'home-120m-1'
    WHEN p_service_id = '90m'  AND p_tipe = 'HOME_SERVICE' AND p_orang = 2 THEN 'home-90m-2'
    ELSE NULL END;
$function$;

CREATE OR REPLACE FUNCTION public._hitung_travel(p_tipe tipe_lokasi, p_jarak_meter numeric)
 RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_gratis numeric; v_tarif numeric;
BEGIN
  IF p_tipe = 'DI_TEMPAT' THEN RETURN 0; END IF;
  SELECT value::numeric INTO v_gratis FROM public.operational_settings WHERE key = 'travel_gratis_meter';
  SELECT value::numeric INTO v_tarif  FROM public.operational_settings WHERE key = 'travel_tarif_per_meter';
  IF v_gratis IS NULL OR v_tarif IS NULL THEN RAISE EXCEPTION 'Aturan travel fee belum tersedia'; END IF;
  IF p_jarak_meter IS NULL OR p_jarak_meter < 0 OR p_jarak_meter::text = 'NaN' THEN RAISE EXCEPTION 'Jarak tempuh wajib untuk Home Service'; END IF;
  RETURN round(greatest(p_jarak_meter - v_gratis, 0) * v_tarif, 0);
END;
$function$;

-- Mesin harga tunggal. p_hari NULL = hari ini WIB. Dipakai create_booking_server, create_booking, dan RPC quote.
CREATE OR REPLACE FUNCTION public._hitung_harga(p_service_id text, p_tipe tipe_lokasi, p_orang smallint, p_travel numeric, p_hari date DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_paket text; v_harga numeric; v_dasar numeric; v_step numeric; v_level integer := 0;
  v_cfg jsonb; v_promo jsonb; v_tipe text; v_nilai numeric; v_mulai date; v_akhir date;
  v_hari date; v_harga_level numeric; v_travel numeric; v_subtotal numeric;
  v_aktif boolean := false; v_diskon numeric := 0;
BEGIN
  v_paket := public._paket_id(p_service_id, p_tipe, p_orang);
  IF v_paket IS NULL THEN RAISE EXCEPTION 'Paket yang dipilih tidak valid'; END IF;
  SELECT harga INTO v_harga FROM public.services WHERE id = p_service_id AND aktif = true;
  IF v_harga IS NULL THEN RAISE EXCEPTION 'Layanan tidak ditemukan'; END IF;

  v_dasar := CASE WHEN v_paket = 'home-90m-2' THEN 120000 ELSE v_harga * p_orang END;
  v_step  := CASE WHEN v_paket = 'home-90m-2' THEN 20000 ELSE 10000 END;
  v_hari  := coalesce(p_hari, timezone('Asia/Jakarta', now())::date);

  -- Baca konfigurasi; rusak/hilang => Dasar tanpa promo (fail-safe).
  BEGIN
    SELECT value INTO v_cfg FROM public.operational_settings WHERE key = 'harga_paket_' || v_paket;
    IF v_cfg IS NOT NULL AND jsonb_typeof(v_cfg) = 'object' THEN
      IF (v_cfg->>'level') ~ '^[0-5]$' THEN v_level := (v_cfg->>'level')::integer; END IF;
      v_promo := v_cfg->'promo';
      IF v_promo IS NOT NULL AND jsonb_typeof(v_promo) = 'object' THEN
        v_tipe  := v_promo->>'tipe';
        v_nilai := (v_promo->>'nilai')::numeric;
        v_mulai := (v_promo->>'mulai')::date;
        v_akhir := (v_promo->>'akhir')::date;
        v_aktif := v_tipe IN ('PERSEN','NOMINAL') AND v_nilai IS NOT NULL AND v_nilai > 0
                   AND v_mulai IS NOT NULL AND v_akhir IS NOT NULL AND v_hari BETWEEN v_mulai AND v_akhir
                   AND (v_tipe <> 'PERSEN' OR v_nilai IN (5,10,15,20,25,30))
                   AND (v_tipe <> 'NOMINAL' OR v_nilai = trunc(v_nilai));
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '_hitung_harga konfigurasi tidak terbaca (fail-safe ke Dasar): %', SQLSTATE;
    v_level := 0; v_aktif := false;
  END;

  v_harga_level := v_dasar + v_level * v_step;
  v_travel := round(greatest(coalesce(p_travel, 0), 0), 0);
  v_subtotal := v_harga_level + v_travel;

  IF v_aktif THEN
    v_diskon := CASE WHEN v_tipe = 'PERSEN' THEN round(v_subtotal * v_nilai / 100, 0) ELSE v_nilai END;
    v_diskon := least(greatest(v_diskon, 0), v_subtotal);
  ELSE
    v_tipe := NULL; v_nilai := NULL; v_mulai := NULL; v_akhir := NULL;
  END IF;

  RETURN jsonb_build_object(
    'paket_id', v_paket, 'harga_dasar', v_dasar, 'level', v_level, 'harga_level', v_harga_level,
    'travel_fee', v_travel, 'subtotal', v_subtotal, 'promo_aktif', v_aktif,
    'promo_tipe', v_tipe, 'promo_nilai', v_nilai, 'promo_mulai', v_mulai, 'promo_akhir', v_akhir,
    'diskon', v_diskon, 'total', v_subtotal - v_diskon);
END;
$function$;

REVOKE ALL ON FUNCTION public._paket_id(text, tipe_lokasi, smallint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._hitung_travel(tipe_lokasi, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._hitung_harga(text, tipe_lokasi, smallint, numeric, date) FROM PUBLIC, anon, authenticated;

-- 5. RPC publik (baca saja): rincian harga untuk katalog & form booking. Tanpa data sensitif.
CREATE OR REPLACE FUNCTION public.hitung_harga_booking(p_service_id text, p_tipe_lokasi tipe_lokasi, p_jumlah_orang smallint, p_jarak_meter numeric DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  RETURN public._hitung_harga(p_service_id, p_tipe_lokasi, p_jumlah_orang,
           CASE WHEN p_tipe_lokasi = 'HOME_SERVICE' THEN public._hitung_travel(p_tipe_lokasi, coalesce(p_jarak_meter, 0)) ELSE 0 END);  -- jarak belum ada = pratinjau tanpa travel
END;
$function$;

-- Katalog: 5 paket. Detail promo mentah (belum mulai/sudah berakhir) hanya terlihat Admin.
CREATE OR REPLACE FUNCTION public.harga_paket_aktif()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_rows jsonb := '[]'::jsonb; v_h jsonb; v_cfg jsonb; v_admin boolean; r record;
BEGIN
  v_admin := coalesce(public.is_admin(), false);
  FOR r IN SELECT * FROM (VALUES
      (1,'sules-90m-1','90m','DI_TEMPAT'::tipe_lokasi,1::smallint),
      (2,'sules-120m-1','120m','DI_TEMPAT'::tipe_lokasi,1::smallint),
      (3,'home-90m-1','90m','HOME_SERVICE'::tipe_lokasi,1::smallint),
      (4,'home-120m-1','120m','HOME_SERVICE'::tipe_lokasi,1::smallint),
      (5,'home-90m-2','90m','HOME_SERVICE'::tipe_lokasi,2::smallint)
    ) AS t(urut, paket_id, service_id, tipe, orang) ORDER BY urut LOOP
    v_h := public._hitung_harga(r.service_id, r.tipe, r.orang, 0);
    v_cfg := NULL;
    IF v_admin THEN
      SELECT value->'promo' INTO v_cfg FROM public.operational_settings WHERE key = 'harga_paket_' || r.paket_id;
    END IF;
    v_rows := v_rows || jsonb_build_array(
      (v_h - 'travel_fee' - 'subtotal' - 'diskon' - 'total')
      || jsonb_build_object('promo_konfigurasi', v_cfg));
  END LOOP;
  RETURN v_rows;
END;
$function$;

REVOKE ALL ON FUNCTION public.hitung_harga_booking(text, tipe_lokasi, smallint, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.harga_paket_aktif() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hitung_harga_booking(text, tipe_lokasi, smallint, numeric) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.harga_paket_aktif() TO anon, authenticated;

-- 6. RPC Admin: atur level & promo satu paket.
CREATE OR REPLACE FUNCTION public.admin_set_harga_paket(p_paket_id text, p_level integer, p_promo_tipe text DEFAULT NULL, p_promo_nilai numeric DEFAULT NULL, p_promo_mulai date DEFAULT NULL, p_promo_akhir date DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_tipe text; v_promo jsonb;
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'Hanya Admin yang boleh mengubah harga';
  END IF;
  IF p_paket_id IS NULL OR p_paket_id NOT IN ('sules-90m-1','sules-120m-1','home-90m-1','home-120m-1','home-90m-2') THEN
    RAISE EXCEPTION 'Paket tidak valid';
  END IF;
  IF p_level IS NULL OR p_level < 0 OR p_level > 5 THEN RAISE EXCEPTION 'Level harga harus 0 (Dasar) sampai 5'; END IF;

  v_tipe := upper(nullif(btrim(coalesce(p_promo_tipe, '')), ''));
  IF v_tipe IS NULL OR v_tipe = 'TANPA' THEN
    v_promo := '{"tipe":null,"nilai":null,"mulai":null,"akhir":null}'::jsonb;
  ELSE
    IF v_tipe NOT IN ('PERSEN','NOMINAL') THEN RAISE EXCEPTION 'Jenis promo tidak valid'; END IF;
    IF p_promo_nilai IS NULL OR p_promo_nilai <= 0 THEN RAISE EXCEPTION 'Nilai promo wajib diisi'; END IF;
    IF v_tipe = 'PERSEN' AND p_promo_nilai NOT IN (5,10,15,20,25,30) THEN
      RAISE EXCEPTION 'Persentase promo harus 5, 10, 15, 20, 25, atau 30';
    END IF;
    IF v_tipe = 'NOMINAL' AND (p_promo_nilai <> trunc(p_promo_nilai) OR p_promo_nilai > 1000000) THEN
      RAISE EXCEPTION 'Potongan rupiah harus bilangan bulat dan tidak lebih dari Rp1.000.000';
    END IF;
    IF p_promo_mulai IS NULL OR p_promo_akhir IS NULL THEN RAISE EXCEPTION 'Tanggal mulai dan akhir promo wajib diisi'; END IF;
    IF p_promo_akhir < p_promo_mulai THEN RAISE EXCEPTION 'Tanggal akhir promo tidak boleh sebelum tanggal mulai'; END IF;
    v_promo := jsonb_build_object('tipe', v_tipe, 'nilai', p_promo_nilai, 'mulai', p_promo_mulai, 'akhir', p_promo_akhir);
  END IF;

  INSERT INTO public.operational_settings (key, value)
  VALUES ('harga_paket_' || p_paket_id, jsonb_build_object('level', p_level, 'promo', v_promo))
  ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now();

  RETURN jsonb_build_object('paket_id', p_paket_id, 'level', p_level, 'promo', v_promo);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_set_harga_paket(text, integer, text, numeric, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_harga_paket(text, integer, text, numeric, date, date) TO authenticated;

-- 7. create_booking_server: definisi produksi 20261013 + mesin harga (validasi lain TIDAK diubah).
CREATE OR REPLACE FUNCTION public.create_booking_server(p_customer_id uuid, p_nama text, p_wa text, p_service_id text, p_jumlah_orang smallint, p_tanggal date, p_jam_mulai time without time zone, p_tipe_lokasi tipe_lokasi, p_alamat text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_jarak_meter numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_service public.services%rowtype;
  v_durasi_menit integer;
  v_booking public.bookings%rowtype;
  v_sesi_tutup text;
  v_h jsonb;
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

  -- Harga: mesin tunggal (level + travel + promo), dihitung di server.
  v_h := public._hitung_harga(p_service_id, p_tipe_lokasi, p_jumlah_orang,
           public._hitung_travel(p_tipe_lokasi, p_jarak_meter));

  INSERT INTO public.customers (id, nama, wa)
  VALUES (p_customer_id, btrim(p_nama), btrim(p_wa))
  ON CONFLICT (id) DO UPDATE SET nama = excluded.nama, wa = excluded.wa;

  INSERT INTO public.bookings (
    customer_id, nama_pelanggan, wa_pelanggan, service_id, jumlah_orang, tanggal, jam_mulai,
    durasi_menit, tipe_lokasi, alamat, lat, lng, jarak_meter, service_price, travel_fee, status,
    harga_dasar, level_harga, promo_tipe, promo_nilai, promo_mulai, promo_akhir, diskon
  ) VALUES (
    p_customer_id, btrim(p_nama), btrim(p_wa), p_service_id, p_jumlah_orang, p_tanggal, p_jam_mulai,
    v_durasi_menit, p_tipe_lokasi, p_alamat, p_lat, p_lng,
    CASE WHEN p_tipe_lokasi = 'HOME_SERVICE' THEN p_jarak_meter ELSE NULL END,
    (v_h->>'harga_level')::numeric, (v_h->>'travel_fee')::numeric, 'MENUNGGU',
    (v_h->>'harga_dasar')::numeric, (v_h->>'level')::smallint, v_h->>'promo_tipe',
    (v_h->>'promo_nilai')::numeric, (v_h->>'promo_mulai')::date, (v_h->>'promo_akhir')::date,
    (v_h->>'diskon')::numeric
  ) RETURNING * INTO v_booking;

  RETURN jsonb_build_object(
    'booking_id', v_booking.id, 'access_token', v_booking.access_token, 'status', v_booking.status,
    'service_price', v_booking.service_price, 'travel_fee', v_booking.travel_fee,
    'subtotal', v_booking.subtotal, 'diskon', v_booking.diskon, 'grand_total', v_booking.grand_total,
    'harga_dasar', v_booking.harga_dasar, 'level_harga', v_booking.level_harga,
    'promo_tipe', v_booking.promo_tipe, 'promo_nilai', v_booking.promo_nilai);
END;
$function$;

-- 8. create_booking (RPC lama; tidak dapat dieksekusi anon/authenticated sekarang): hanya bagian harga diselaraskan.
CREATE OR REPLACE FUNCTION public.create_booking(p_nama text, p_wa text, p_service_id text, p_jumlah_orang smallint, p_tanggal date, p_jam_mulai time without time zone, p_tipe_lokasi tipe_lokasi, p_alamat text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_jarak_meter numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_service services%rowtype;
  v_customer_id uuid;
  v_h jsonb;
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

  v_h := public._hitung_harga(p_service_id, p_tipe_lokasi, p_jumlah_orang,
           public._hitung_travel(p_tipe_lokasi, p_jarak_meter));

  insert into bookings(
    customer_id,nama_pelanggan,wa_pelanggan,service_id,jumlah_orang,tanggal,jam_mulai,durasi_menit,
    tipe_lokasi,alamat,lat,lng,jarak_meter,service_price,travel_fee,status,
    harga_dasar,level_harga,promo_tipe,promo_nilai,promo_mulai,promo_akhir,diskon
  ) values(
    v_customer_id,btrim(p_nama),btrim(p_wa),p_service_id,p_jumlah_orang,p_tanggal,p_jam_mulai,v_service.durasi_menit,
    p_tipe_lokasi,p_alamat,p_lat,p_lng,p_jarak_meter,(v_h->>'harga_level')::numeric,(v_h->>'travel_fee')::numeric,'MENUNGGU',
    (v_h->>'harga_dasar')::numeric,(v_h->>'level')::smallint,v_h->>'promo_tipe',
    (v_h->>'promo_nilai')::numeric,(v_h->>'promo_mulai')::date,(v_h->>'promo_akhir')::date,(v_h->>'diskon')::numeric
  ) returning * into v_booking;

  return jsonb_build_object('booking_id',v_booking.id,'access_token',v_booking.access_token,'status',v_booking.status,
    'service_price',v_booking.service_price,'travel_fee',v_booking.travel_fee,'subtotal',v_booking.subtotal,
    'diskon',v_booking.diskon,'grand_total',v_booking.grand_total);
end;
$function$;

-- Keamanan: booking pelanggan HANYA lewat Edge Function create-booking (validasi profil + jarak Google Routes).
-- Kedua RPC tidak boleh dieksekusi anon/authenticated (sama dengan produksi saat ini; di sini ditegaskan eksplisit).
REVOKE ALL ON FUNCTION public.create_booking_server(uuid, text, text, text, smallint, date, time without time zone, tipe_lokasi, text, double precision, double precision, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_booking(text, text, text, smallint, date, time without time zone, tipe_lokasi, text, double precision, double precision, numeric) FROM PUBLIC, anon, authenticated;

-- 9. Daftar booking Admin: tambah kolom rincian harga. Tipe kembalian berubah => DROP + CREATE, hak akses dipulihkan
--    persis seperti produksi (authenticated + service_role; tanpa anon/PUBLIC). is_admin() tetap dicek di dalam.
DROP FUNCTION public.list_bookings_admin(booking_status);
CREATE FUNCTION public.list_bookings_admin(p_status booking_status DEFAULT NULL::booking_status)
 RETURNS TABLE(id uuid, nama text, wa text, service_id text, jumlah_orang smallint, tanggal date, jam_mulai time without time zone, tipe_lokasi tipe_lokasi, alamat text, lat double precision, lng double precision, jarak_meter numeric, service_price numeric, travel_fee numeric, grand_total numeric, status booking_status, created_at timestamp with time zone, harga_dasar numeric, level_harga smallint, promo_tipe text, promo_nilai numeric, diskon numeric, subtotal numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not is_admin() then
    raise exception 'Hanya admin yang boleh melihat daftar booking';
  end if;

  return query
    select b.id, coalesce(b.nama_pelanggan, c.nama), coalesce(b.wa_pelanggan, c.wa), b.service_id, b.jumlah_orang, b.tanggal, b.jam_mulai,
           b.tipe_lokasi, b.alamat, b.lat, b.lng, b.jarak_meter,
           b.service_price, b.travel_fee, b.grand_total, b.status, b.created_at,
           b.harga_dasar, b.level_harga, b.promo_tipe, b.promo_nilai, b.diskon, b.subtotal
    from bookings b
    join customers c on c.id = b.customer_id
    where (p_status is null or b.status = p_status)
    order by b.created_at desc;
end;
$function$;
REVOKE ALL ON FUNCTION public.list_bookings_admin(booking_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_bookings_admin(booking_status) TO authenticated, service_role;

DROP FUNCTION public.list_bookings_admin_period(date, date, booking_status);
CREATE FUNCTION public.list_bookings_admin_period(p_start_date date, p_end_date date, p_status booking_status DEFAULT NULL::booking_status)
 RETURNS TABLE(id uuid, nama text, wa text, service_id text, jumlah_orang smallint, tanggal date, jam_mulai time without time zone, tipe_lokasi tipe_lokasi, alamat text, lat double precision, lng double precision, jarak_meter numeric, service_price numeric, travel_fee numeric, grand_total numeric, status booking_status, created_at timestamp with time zone, harga_dasar numeric, level_harga smallint, promo_tipe text, promo_nilai numeric, diskon numeric, subtotal numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not is_admin() then
    raise exception 'Hanya admin yang boleh melihat daftar booking';
  end if;

  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'Rentang tanggal tidak valid';
  end if;

  return query
    select b.id, coalesce(b.nama_pelanggan, c.nama), coalesce(b.wa_pelanggan, c.wa), b.service_id, b.jumlah_orang, b.tanggal, b.jam_mulai,
           b.tipe_lokasi, b.alamat, b.lat, b.lng, b.jarak_meter,
           b.service_price, b.travel_fee, b.grand_total, b.status, b.created_at,
           b.harga_dasar, b.level_harga, b.promo_tipe, b.promo_nilai, b.diskon, b.subtotal
    from bookings b
    join customers c on c.id = b.customer_id
    where b.tanggal between p_start_date and p_end_date
      and (p_status is null or b.status = p_status)
    order by b.created_at desc;
end;
$function$;
REVOKE ALL ON FUNCTION public.list_bookings_admin_period(date, date, booking_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_bookings_admin_period(date, date, booking_status) TO authenticated, service_role;

COMMIT;
