\set ON_ERROR_STOP on
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
end $$;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth, public to anon, authenticated;
-- meniru default Supabase: fungsi baru di schema public otomatis bisa dieksekusi anon/authenticated (kasus terburuk)
alter default privileges in schema public grant execute on functions to anon, authenticated;
create type booking_status as enum ('MENUNGGU','DITERIMA','DITOLAK','SELESAI','DIBATALKAN');
create type tipe_lokasi as enum ('DI_TEMPAT','HOME_SERVICE');
create table admins(id uuid primary key);
create table operational_settings(key text primary key, value jsonb not null);
insert into operational_settings values
  ('jam_operasional_pagi','{"mulai":"08:00","selesai":"15:00"}'),
  ('jam_operasional_malam','{"mulai":"19:00","selesai":"24:00"}');
create table bookings(
  id uuid primary key default gen_random_uuid(), customer_id uuid,
  tanggal date not null, jam_mulai time not null, durasi_menit integer not null,
  status booking_status not null default 'MENUNGGU', catatan_penolakan text);
-- ===== definisi ASLI dari production (pg_get_functiondef) =====
CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from admins where id = auth.uid()
  );
$function$;

CREATE OR REPLACE FUNCTION public._dalam_jam_operasional(p_jam_mulai time without time zone, p_durasi_menit integer)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pagi jsonb;
  v_malam jsonb;
  v_start_minutes integer;
  v_pagi_open integer;
  v_pagi_close integer;
  v_malam_open integer;
  v_malam_close integer;
BEGIN
  IF p_jam_mulai IS NULL OR p_durasi_menit IS NULL OR p_durasi_menit <= 0 THEN
    RETURN false;
  END IF;
  IF extract(second FROM p_jam_mulai) <> 0 OR mod(extract(minute FROM p_jam_mulai)::integer, 30) <> 0 THEN
    RETURN false;
  END IF;

  SELECT value INTO v_pagi FROM operational_settings WHERE key = 'jam_operasional_pagi';
  SELECT value INTO v_malam FROM operational_settings WHERE key = 'jam_operasional_malam';
  IF v_pagi IS NULL OR v_malam IS NULL THEN
    RETURN false;
  END IF;

  v_start_minutes := extract(hour FROM p_jam_mulai)::integer * 60 + extract(minute FROM p_jam_mulai)::integer;
  v_pagi_open := split_part(v_pagi ->> 'mulai', ':', 1)::integer * 60 + split_part(v_pagi ->> 'mulai', ':', 2)::integer;
  v_pagi_close := split_part(v_pagi ->> 'selesai', ':', 1)::integer * 60 + split_part(v_pagi ->> 'selesai', ':', 2)::integer;
  v_malam_open := split_part(v_malam ->> 'mulai', ':', 1)::integer * 60 + split_part(v_malam ->> 'mulai', ':', 2)::integer;
  v_malam_close := split_part(v_malam ->> 'selesai', ':', 1)::integer * 60 + split_part(v_malam ->> 'selesai', ':', 2)::integer;

  IF v_start_minutes >= v_pagi_open AND v_start_minutes + p_durasi_menit <= v_pagi_close THEN
    RETURN true;
  END IF;
  IF v_start_minutes >= v_malam_open AND v_start_minutes + p_durasi_menit <= v_malam_close THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$function$;
revoke all on function public._dalam_jam_operasional(time, integer) from public, anon, authenticated;
