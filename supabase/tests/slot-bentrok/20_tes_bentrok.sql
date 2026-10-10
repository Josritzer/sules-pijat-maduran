\set ON_ERROR_STOP on
-- tiap kasus memakai tanggal sendiri. (nama, lawan_jam, lawan_dur, lawan_status, calon_jam, calon_dur, harapan)
do $$
declare k record; d date := date '2027-03-01'; ex uuid; cand uuid; got text; n int := 0;
begin
  for k in select * from (values
    ('C01 tumpang tindih nyata (10:00+90 vs 11:00+90)',            time '10:00', 90,  'DITERIMA', time '11:00', 90,  'BENTROK'),
    ('C02 waktu sama persis',                                      time '10:00', 90,  'DITERIMA', time '10:00', 90,  'BENTROK'),
    ('C03 berurutan tanpa tumpang tindih (10:00+90 lalu 11:30)',   time '10:00', 90,  'DITERIMA', time '11:30', 90,  'OK'),
    ('C04 calon membungkus lawan (12:00+90 vs 11:00+180)',         time '12:00', 90,  'DITERIMA', time '11:00', 180, 'BENTROK'),
    ('C05 akhir 24:00: 22:30+90 vs pagi 08:00+90',                 time '22:30', 90,  'DITERIMA', time '08:00', 90,  'OK'),
    ('C06 akhir 24:00: 21:00+180 vs 19:00+90',                     time '21:00', 180, 'DITERIMA', time '19:00', 90,  'OK'),
    ('C07 akhir 24:00: 21:00+180 vs 21:30+90 (nyata bentrok)',     time '21:00', 180, 'DITERIMA', time '21:30', 90,  'BENTROK'),
    ('C08 akhir 24:00: 21:00+180 vs 22:00+90 (nyata bentrok)',     time '21:00', 180, 'DITERIMA', time '22:00', 90,  'BENTROK'),
    ('C09 malam berurutan: 21:00+90 lalu 22:30+90 (akhir 24:00)',  time '21:00', 90,  'DITERIMA', time '22:30', 90,  'OK'),
    ('C10 dua booking berakhir 24:00: 22:30+90 vs 22:00+120',      time '22:30', 90,  'DITERIMA', time '22:00', 120, 'BENTROK'),
    ('C11 malam berurutan: 19:00+90 lalu 20:30+90',                time '19:00', 90,  'DITERIMA', time '20:30', 90,  'OK'),
    ('C12 DITOLAK tidak memblokir',                                time '10:00', 90,  'DITOLAK',  time '10:00', 90,  'OK'),
    ('C13 DIBATALKAN tidak memblokir',                             time '10:00', 90,  'DIBATALKAN', time '10:00', 90, 'OK'),
    ('C14 MENUNGGU tidak memblokir (aturan tidak diubah)',         time '10:00', 90,  'MENUNGGU', time '10:00', 90,  'OK'),
    ('C15 SELESAI tidak dihitung (aturan saat ini, tidak diubah)', time '10:00', 90,  'SELESAI',  time '10:00', 90,  'OK'),
    ('C16 di luar jam operasional (15:00+90)',                     null,         null, null,       time '15:00', 90,  'DI_LUAR_JAM_OPERASIONAL'),
    ('C17 melewati 24:00 (23:00+90)',                              null,         null, null,       time '23:00', 90,  'DI_LUAR_JAM_OPERASIONAL')
  ) as v(nama, lj, ld, ls, cj, cd, harapan)
  loop
    n := n + 1; d := d + 1;
    if k.lj is not null then ex := t.bk(d, k.lj, k.ld, k.ls::booking_status); end if;
    cand := t.bk(d, k.cj, k.cd, 'MENUNGGU');
    got := t.acc(cand);
    insert into t.hasil values ('bentrok', k.nama, k.harapan, got, got = k.harapan);
  end loop;
end $$;
-- aturan jam operasional di sisi database (harus tetap sesuai: siang 08-15, malam 19-24, interval 30)
insert into t.hasil
select 'jam', format('%s mulai %s durasi %s', 'DB', jam, dur), harapan::text, public._dalam_jam_operasional(jam::time, dur)::text,
       public._dalam_jam_operasional(jam::time, dur) = harapan
from (values
 ('08:00',90,true),('13:30',90,true),('14:00',90,false),('19:00',90,true),('22:30',90,true),('23:00',90,false),
 ('13:00',120,true),('13:30',120,false),('22:00',120,true),('22:30',120,false),
 ('12:00',180,true),('12:30',180,false),('21:00',180,true),('21:30',180,false),
 ('07:30',90,false),('18:30',90,false),('22:15',90,false),('15:00',90,false)) as x(jam,dur,harapan);
