#!/bin/bash
# Pakai: bash supabase/tests/harga/run.sh  (butuh Postgres lokal 127.0.0.1:5544; TIDAK menyentuh Supabase remote)
set -e; cd "$(dirname "$0")/../../.."
P="psql -h 127.0.0.1 -p 5544 -U postgres -qAt -v ON_ERROR_STOP=1"
$P -d postgres -c "drop database if exists hg" -c "create database hg" >/dev/null
for f in supabase/tests/sesi/00_base.sql supabase/tests/harga/05_stub_tambahan.sql supabase/migrations/20261009062845_paket5_two_clients_180_minutes.sql supabase/migrations/20261010_slot_terisi_dan_bentrok_tengah_malam.sql supabase/migrations/20261013_sesi_buka_tutup.sql supabase/migrations/20261014_harga_bertingkat_promo.sql; do $P -d hg -f $f >/dev/null; done
psql -h 127.0.0.1 -p 5544 -U postgres -d hg -qAt -f supabase/tests/harga/10_tes.sql 2>&1 | grep -v "^SET\|^$"
