#!/bin/bash
# Uji rollback: migrasi -> booking tanpa diskon -> rollback OK & data utuh -> migrasi ulang; lalu jalur guard (ada diskon -> rollback ditolak).
# Pakai: bash supabase/tests/harga/20_tes_rollback.sh   (Postgres lokal 127.0.0.1:5544; tidak menyentuh remote)
set -e; cd "$(dirname "$0")/../../.."
P="psql -h 127.0.0.1 -p 5544 -U postgres -qAt -v ON_ERROR_STOP=1"; R="psql -h 127.0.0.1 -p 5544 -U postgres -qAt"
M=supabase/migrations; RB=supabase/rollbacks/20261014_harga_bertingkat_promo_rollback.sql; MIG=$M/20261014_harga_bertingkat_promo.sql
hasil=0; gagal=0; cek(){ if [ "$2" = "1" ]; then echo "PASS | $1"; else echo "FAIL | $1 -> $3"; gagal=$((gagal+1)); fi; hasil=$((hasil+1)); }
$P -d postgres -c "drop database if exists hrb" -c "create database hrb" >/dev/null
for f in supabase/tests/sesi/00_base.sql supabase/tests/harga/05_stub_tambahan.sql $M/20261009062845_paket5_two_clients_180_minutes.sql $M/20261010_slot_terisi_dan_bentrok_tengah_malam.sql $M/20261013_sesi_buka_tutup.sql; do $P -d hrb -f $f >/dev/null; done
# baseline mirip produksi: create_booking & create_booking_server tidak dapat dieksekusi anon/authenticated
$P -d hrb -c "REVOKE ALL ON FUNCTION public.create_booking_server(uuid,text,text,text,smallint,date,time without time zone,tipe_lokasi,text,double precision,double precision,numeric) FROM PUBLIC, anon, authenticated" -c "REVOKE ALL ON FUNCTION public.create_booking(text,text,text,smallint,date,time without time zone,tipe_lokasi,text,double precision,double precision,numeric) FROM PUBLIC, anon, authenticated" >/dev/null
SNAP_FN="select md5(string_agg(pg_get_functiondef(p.oid), '' order by p.proname)) from pg_proc p where pronamespace='public'::regnamespace and proname in ('create_booking','create_booking_server','list_bookings_admin','list_bookings_admin_period')"
SNAP_ACL="select string_agg(p.proname||':'||coalesce(p.proacl::text,'-'), ',' order by p.proname) from pg_proc p where pronamespace='public'::regnamespace and proname in ('create_booking','create_booking_server','list_bookings_admin','list_bookings_admin_period')"
SNAP_TOT="select string_agg(nama_pelanggan||'='||service_price||'/'||travel_fee||'/'||grand_total, ',' order by nama_pelanggan) from bookings"
SNAP_COLS="select string_agg(column_name||':'||data_type||':'||is_generated, ',' order by column_name) from information_schema.columns where table_name='bookings'"
F0=$($P -d hrb -c "$SNAP_FN"); A0=$($P -d hrb -c "$SNAP_ACL"); T0=$($P -d hrb -c "$SNAP_TOT"); C0=$($P -d hrb -c "$SNAP_COLS")
$P -d hrb -f $MIG >/dev/null
$P -d hrb -c "insert into bookings(customer_id,nama_pelanggan,wa_pelanggan,service_id,jumlah_orang,tanggal,jam_mulai,durasi_menit,tipe_lokasi,service_price,travel_fee,status,harga_dasar,level_harga,diskon) values ('11111111-1111-1111-1111-111111111111','Baru','081','90m',1,'2027-01-01','10:00',90,'DI_TEMPAT',70000,0,'MENUNGGU',60000,1,0)" >/dev/null
$P -d hrb -f $RB >/dev/null 2>/var/tmp/rb_err.txt && ok=1 || ok=0; cek "rollback berjalan tanpa error (tanpa booking ber-diskon)" $ok "$(head -2 /var/tmp/rb_err.txt)"
F1=$($P -d hrb -c "$SNAP_FN"); A1=$($P -d hrb -c "$SNAP_ACL"); C1=$($P -d hrb -c "$SNAP_COLS"); T1=$($P -d hrb -c "$SNAP_TOT")
[ "$F0" = "$F1" ] && ok=1 || ok=0; cek "definisi 4 fungsi kembali persis seperti sebelum migrasi (md5)" $ok "$F0 vs $F1"
[ "$A0" = "$A1" ] && ok=1 || ok=0; cek "hak akses 4 fungsi kembali persis seperti sebelum migrasi" $ok "$A0 vs $A1"
[ "$C0" = "$C1" ] && ok=1 || ok=0; cek "kolom bookings kembali persis (grand_total GENERATED lagi)" $ok "$C0 vs $C1"
echo "$T1" | grep -q "Lama1=80000/332.50/80332.50" && echo "$T1" | grep -q "Baru=70000/0/70000" && ok=1 || ok=0; cek "total booking lama & booking baru tanpa diskon tetap sama setelah rollback" $ok "$T1"
n=$($P -d hrb -c "select count(*) from operational_settings where key like 'harga\_paket\_%'"); [ "$n" = "0" ] && ok=1 || ok=0; cek "konfigurasi harga_paket_* dibersihkan" $ok "$n"
n=$($P -d hrb -c "select count(*) from pg_proc where pronamespace='public'::regnamespace and proname in ('_hitung_harga','_hitung_travel','_paket_id','hitung_harga_booking','harga_paket_aktif','admin_set_harga_paket')"); [ "$n" = "0" ] && ok=1 || ok=0; cek "6 fungsi baru terhapus" $ok "$n"
$P -d hrb -f $MIG >/dev/null 2>/var/tmp/rb_err.txt && ok=1 || ok=0; cek "migrasi dapat diterapkan ulang setelah rollback" $ok "$(head -2 /var/tmp/rb_err.txt)"
# jalur guard
$P -d hrb -c "update bookings set promo_tipe='NOMINAL', promo_nilai=5000, promo_mulai='2027-01-01', promo_akhir='2027-01-02', diskon=5000 where nama_pelanggan='Baru'" >/dev/null
$P -d hrb -f $RB >/dev/null 2>/var/tmp/rb_err.txt && ok=0 || ok=1; cek "rollback DITOLAK bila ada booking ber-diskon" $ok "tidak ditolak"
grep -q "ada booking dengan diskon" /var/tmp/rb_err.txt && ok=1 || ok=0; cek "pesan guard jelas" $ok "$(head -2 /var/tmp/rb_err.txt)"
n=$($P -d hrb -c "select count(*) from pg_proc where pronamespace='public'::regnamespace and proname='admin_set_harga_paket'"); d=$($P -d hrb -c "select diskon from bookings where nama_pelanggan='Baru'"); [ "$n" = "1" ] && [ "$d" = "5000" ] && ok=1 || ok=0; cek "setelah guard menolak: tidak ada perubahan (fungsi baru masih ada, diskon utuh)" $ok "fn=$n diskon=$d"
echo "RINGKAS: $hasil pemeriksaan, $gagal gagal"; [ $gagal -eq 0 ]
