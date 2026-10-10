# Tes slot bentrok (data buatan, database lokal sementara)

Bukan untuk production. Semua tes memakai PostgreSQL lokal dengan tabel tiruan; RLS Supabase tidak ikut ditiru
(migrasi tidak mengubah RLS). Jalur di skrip (`/var/tmp/pgt`, port 55432) adalah lingkungan sementara; sesuaikan bila dijalankan ulang.

- `run.sh <db> old|new` – bangun DB, pasang versi lama (rollback file) atau baru (migrasi), jalankan 17 kasus bentrok + matriks jam.
- `30_slot_terisi.sql`, `31_acl.sql` – isi dan hak akses `get_slot_terisi`.
- `conc.sh <db>` – tes serentak (kunci advisory per tanggal).
- `gen_equiv.js` – membuat 7.488 kasus yang membandingkan fungsi JS asli di `index.html` dengan `accept_booking` SQL.
- `svc_test.js` – uji `getSlotTerisi` dengan klien tiruan.
