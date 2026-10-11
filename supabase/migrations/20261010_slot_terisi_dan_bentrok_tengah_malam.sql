-- USULAN — BELUM DIJALANKAN DI PRODUCTION. Tunggu persetujuan pemilik sebelum dieksekusi.
--
-- Isi:
--  1) public.get_slot_terisi(date): fungsi BACA-SAJA agar form booking pelanggan bisa menandai
--     slot yang bentrok dengan booking DITERIMA. Hanya mengembalikan dua angka (menit mulai
--     dan menit selesai); tanpa id, nama, WhatsApp, alamat, koordinat, harga, atau id pelanggan.
--  2) public.accept_booking(uuid): perbaikan HITUNG BENTROK saja. Cara lama memakai OVERLAPS pada
--     tipe jam; jam + durasi yang berakhir tepat 24:00 berputar menjadi 00:00 sehingga rentangnya
--     terbalik (mis. 22:30 + 90 menit dibaca sebagai 00:00–22:30). Cara baru memakai hitungan menit.
--
-- Tidak diubah: RLS tabel bookings, jam operasional, durasi, tarif, status, kunci advisory per
-- tanggal, urutan FOR UPDATE, bentuk hasil JSON accept_booking.

-- 1) Fungsi baca-saja untuk slot terisi ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_slot_terisi(p_tanggal date)
RETURNS TABLE (mulai_menit integer, selesai_menit integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT
    (EXTRACT(HOUR FROM b.jam_mulai)::integer * 60 + EXTRACT(MINUTE FROM b.jam_mulai)::integer) AS mulai_menit,
    (EXTRACT(HOUR FROM b.jam_mulai)::integer * 60 + EXTRACT(MINUTE FROM b.jam_mulai)::integer + b.durasi_menit) AS selesai_menit
  FROM public.bookings AS b
  WHERE auth.uid() IS NOT NULL
    AND p_tanggal IS NOT NULL
    AND b.tanggal = p_tanggal
    AND b.status = 'DITERIMA'
    AND b.durasi_menit IS NOT NULL
    AND b.durasi_menit > 0
  ORDER BY 1, 2;
$function$;

REVOKE ALL ON FUNCTION public.get_slot_terisi(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_slot_terisi(date) TO authenticated;

-- 2) accept_booking: hanya blok pencarian bentrok yang berubah ----------------------------------
CREATE OR REPLACE FUNCTION public.accept_booking(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_booking bookings%rowtype;
  v_conflict record;
begin
  if not is_admin() then
    raise exception 'Hanya admin yang boleh menerima booking';
  end if;

  select * into v_booking from bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Booking tidak ditemukan';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_booking.tanggal::text));

  if v_booking.status <> 'MENUNGGU' then
    raise exception 'Booking sudah berstatus % (bukan MENUNGGU)', v_booking.status;
  end if;

  if not _dalam_jam_operasional(v_booking.jam_mulai, v_booking.durasi_menit) then
    return jsonb_build_object('success', false, 'reason', 'DI_LUAR_JAM_OPERASIONAL');
  end if;

  -- Bentrok dihitung dalam menit sejak 00:00 (separuh terbuka: mulai < selesai lawan DAN mulai lawan < selesai).
  -- Booking berurutan (selesai = mulai berikutnya) TIDAK bentrok. Akhir 24:00 = menit 1440, tidak berputar.
  select b.id, b.jam_mulai, b.durasi_menit into v_conflict
  from bookings b
  where b.tanggal = v_booking.tanggal
    and b.status = 'DITERIMA'
    and b.id <> v_booking.id
    and b.durasi_menit is not null
    and b.durasi_menit > 0
    and (extract(hour from v_booking.jam_mulai)::integer * 60 + extract(minute from v_booking.jam_mulai)::integer)
          < (extract(hour from b.jam_mulai)::integer * 60 + extract(minute from b.jam_mulai)::integer + b.durasi_menit)
    and (extract(hour from b.jam_mulai)::integer * 60 + extract(minute from b.jam_mulai)::integer)
          < (extract(hour from v_booking.jam_mulai)::integer * 60 + extract(minute from v_booking.jam_mulai)::integer + v_booking.durasi_menit)
  limit 1;

  if found then
    return jsonb_build_object(
      'success', false,
      'reason', 'BENTROK',
      'conflict_with_booking_id', v_conflict.id
    );
  end if;

  update bookings set status = 'DITERIMA' where id = p_booking_id;

  return jsonb_build_object('success', true, 'booking_id', p_booking_id, 'status', 'DITERIMA');
end;
$function$;

-- Hak akses accept_booking tetap seperti di production (hanya authenticated; pengecekan admin ada di dalam fungsi).
REVOKE ALL ON FUNCTION public.accept_booking(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_booking(uuid) TO authenticated;

-- Pembatalan (rollback) bila diperlukan: jalankan supabase/rollbacks/20261010_slot_terisi_rollback.sql
-- (berisi DROP get_slot_terisi dan definisi lama accept_booking persis seperti di production).
