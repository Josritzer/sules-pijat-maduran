#!/bin/bash
# usage: conc.sh <db>
DB=$1; B=/usr/lib/postgresql/16/bin; P="$B/psql -h 127.0.0.1 -p 55432 -U postgres -d $DB -qAt"
$P -c "create table if not exists t.conc(grp text, nama text, hasil text)" -c "truncate t.conc"
ADM="select set_config('request.jwt.claim.sub','aaaaaaaa-0000-0000-0000-000000000001',false);"
# --- K1: deterministik. Sesi 1 menerima A lalu menahan transaksi 2 dtk; sesi 2 coba menerima B (bentrok) saat itu.
read A B < <($P -c "select t.bk('2027-08-01','20:00',90,'MENUNGGU'), t.bk('2027-08-01','21:00',90,'MENUNGGU')" | tr '|' ' ')
( $P -c "begin" -c "$ADM" -c "select 'S1:'||(public.accept_booking('$A')->>'success')" -c "select pg_sleep(2)" -c "commit" > /var/tmp/pgt/k1_s1.txt 2>&1 ) &
sleep 0.7
( s=$(date +%s.%N); r=$($P -c "$ADM" -c "select coalesce(public.accept_booking('$B')->>'reason', 'OK')" | tail -1); e=$(date +%s.%N); echo "$r $(echo "$e - $s" | bc)" > /var/tmp/pgt/k1_s2.txt ) &
wait
$P -c "insert into t.conc values ('K1','sesi2 harus menunggu lalu BENTROK', '$(cat /var/tmp/pgt/k1_s2.txt)')"
# --- K2: 40 pasangan bentrok pada tanggal berbeda, kedua accept diluncurkan bersamaan
for i in $(seq 1 40); do
  d=$(date -d "2027-09-01 +$i day" +%F)
  read A B < <($P -c "select t.bk('$d','19:00',120,'MENUNGGU'), t.bk('$d','20:00',90,'MENUNGGU')" | tr '|' ' ')
  ( $P -c "$ADM" -c "select coalesce(public.accept_booking('$A')->>'reason','OK')" | tail -1 > /var/tmp/pgt/k2_${i}_a.txt ) &
  ( $P -c "$ADM" -c "select coalesce(public.accept_booking('$B')->>'reason','OK')" | tail -1 > /var/tmp/pgt/k2_${i}_b.txt ) &
done
wait
ok2=0; bad2=0
for i in $(seq 1 40); do a=$(cat /var/tmp/pgt/k2_${i}_a.txt); b=$(cat /var/tmp/pgt/k2_${i}_b.txt); n=0; [ "$a" = OK ] && n=$((n+1)); [ "$b" = OK ] && n=$((n+1)); if [ $n -eq 1 ]; then ok2=$((ok2+1)); else bad2=$((bad2+1)); fi; done
$P -c "insert into t.conc values ('K2','40 pasangan tumpang tindih: tepat 1 OK per pasangan', 'pasangan benar=$ok2 salah=$bad2')"
# --- K3: 10 kandidat saling tumpang tindih pada satu tanggal, semua diaccept bersamaan -> tepat 1 OK
d=2027-10-15; ids=$($P -c "select string_agg(t.bk('$d','19:00'::time + (g*30||' minutes')::interval, 120, 'MENUNGGU')::text, ' ') from generate_series(0,3) g")
for id in $ids; do ( $P -c "$ADM" -c "select coalesce(public.accept_booking('$id')->>'reason','OK')" | tail -1 > /var/tmp/pgt/k3_$id.txt ) & done
wait
okc=0; for id in $ids; do [ "$(cat /var/tmp/pgt/k3_$id.txt)" = OK ] && okc=$((okc+1)); done
$P -c "insert into t.conc values ('K3','4 kandidat 19:00-20:30 saling tumpang tindih, serentak: tepat 1 OK', 'jumlah OK=$okc')"
# --- K4: akhir-malam: pasangan 22:00+120 vs 22:30+90 (keduanya berakhir 24:00) serentak
ok4=0; bad4=0
for i in $(seq 1 20); do
  d=$(date -d "2028-01-01 +$i day" +%F)
  read A B < <($P -c "select t.bk('$d','22:00',120,'MENUNGGU'), t.bk('$d','22:30',90,'MENUNGGU')" | tr '|' ' ')
  ( $P -c "$ADM" -c "select coalesce(public.accept_booking('$A')->>'reason','OK')" | tail -1 > /var/tmp/pgt/k4_${i}_a.txt ) &
  ( $P -c "$ADM" -c "select coalesce(public.accept_booking('$B')->>'reason','OK')" | tail -1 > /var/tmp/pgt/k4_${i}_b.txt ) &
done
wait
for i in $(seq 1 20); do a=$(cat /var/tmp/pgt/k4_${i}_a.txt); b=$(cat /var/tmp/pgt/k4_${i}_b.txt); n=0; [ "$a" = OK ] && n=$((n+1)); [ "$b" = OK ] && n=$((n+1)); if [ $n -eq 1 ]; then ok4=$((ok4+1)); else bad4=$((bad4+1)); fi; done
$P -c "insert into t.conc values ('K4','20 pasangan berakhir 24:00 serentak: tepat 1 OK per pasangan', 'pasangan benar=$ok4 salah=$bad4')"
$P -c "select 'verifikasi DB: tanggal dengan >1 DITERIMA yang tumpang tindih (menit)' , count(*) from bookings a join bookings b on a.tanggal=b.tanggal and a.id<b.id and a.status='DITERIMA' and b.status='DITERIMA' and (extract(hour from a.jam_mulai)*60+extract(minute from a.jam_mulai)) < (extract(hour from b.jam_mulai)*60+extract(minute from b.jam_mulai)+b.durasi_menit) and (extract(hour from b.jam_mulai)*60+extract(minute from b.jam_mulai)) < (extract(hour from a.jam_mulai)*60+extract(minute from a.jam_mulai)+a.durasi_menit)"
$P -c "select grp, nama, hasil from t.conc order by grp"
cat /var/tmp/pgt/k1_s1.txt | tr '\n' ' '; echo
