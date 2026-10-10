-- PEMBATALAN untuk 20261010_slot_terisi_dan_bentrok_tengah_malam.sql
-- Berisi definisi accept_booking(uuid) SEPERTI DI PRODUCTION sebelum perbaikan (diambil dari pg_get_functiondef,
-- 2026-10-10), karena definisi lama tidak ada di folder migrations. Jangan dijalankan kecuali perlu mundur.
-- Catatan: definisi lama ini memiliki cacat hitung bentrok untuk booking yang berakhir tepat 24:00.

DROP FUNCTION IF EXISTS public.get_slot_terisi(date);

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

  select b.id, b.jam_mulai, b.durasi_menit into v_conflict
  from bookings b
  where b.tanggal = v_booking.tanggal
    and b.status = 'DITERIMA'
    and b.id <> v_booking.id
    and (v_booking.jam_mulai, v_booking.jam_mulai + (v_booking.durasi_menit || ' minutes')::interval)
        overlaps (b.jam_mulai, b.jam_mulai + (b.durasi_menit || ' minutes')::interval)
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
