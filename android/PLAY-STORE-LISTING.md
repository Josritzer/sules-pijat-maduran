# Paket persiapan Google Play — SULES PIJAT MADURAN

Diperbarui 7 Oktober 2026 berdasarkan source aplikasi, konfigurasi Android wrapper, dan UI production. Ini materi siap salin ke Play Console; deklarasi Data Safety tetap harus ditinjau dan disetujui pemilik karena hanya pemilik yang mengetahui seluruh praktik layanan pihak ketiga.

## Materi listing

| Field Play Console | Nilai siap pakai | Catatan |
|---|---|---|
| Nama aplikasi | SULES PIJAT MADURAN | Selaras dengan judul website; 20 karakter. |
| Nama launcher Android | Sules Relaxing Massage | Diambil dari manifest PWA. |
| Package ID | `com.bookingpijat.sules` | Sudah ada pada proyek Android; ketersediaannya harus dikonfirmasi saat membuat listing. |
| Version | `1.0.0` | Konfigurasi release. |
| Version code | `2` | Sudah dinaikkan dan dibundel ke release. |
| Target API | Android 16 / API 36 | Source Android saat ini menetapkan target SDK 36. |
| Deskripsi pendek | Pesan layanan pijat Sules di Maduran, pilih jadwal, dan pantau status booking. | 78 karakter; di bawah batas 80 karakter. |
| Kategori yang disarankan | Lifestyle | Rekomendasi untuk aplikasi pemesanan layanan lokal; pilih final di Console. |
| Negara distribusi | Indonesia | Usulan berdasarkan wilayah layanan; konfirmasi pemilik. |
| Bahasa utama | Indonesia | Selaras dengan UI dan layanan. |
| Kebijakan privasi | https://bookingpijat.com/#kebijakan-privasi | Halaman kebijakan yang saat ini dipublikasikan. |
| Resource permintaan hapus akun | https://bookingpijat.com/delete-account.html | Halaman publik; tidak membutuhkan login; permintaan lewat email. |
| Website | https://bookingpijat.com/ | Domain production canonical. |
| Email kontak | srawungjagad3714@gmail.com | Kontak publik yang sudah ada di website. |
| WhatsApp kontak | https://wa.me/6285855603240 | Kontak publik yang sudah ada di website. |

### Deskripsi lengkap (siap salin)

SULES PIJAT MADURAN membantu Anda mengajukan booking layanan pijat di Maduran, Lamongan.

Pilih salah satu dari lima paket, tentukan layanan di Sules atau ke Rumah, lalu pilih tanggal dan waktu. Permintaan booking yang berhasil dikirim berstatus MENUNGGU sampai Admin memprosesnya. Masuk menggunakan email dan kode OTP untuk memeriksa status serta riwayat booking.

Paket yang tersedia:
- Pijat 90 Menit — Rp60.000 di Sules.
- Pijat 2 Jam — Rp80.000 di Sules.
- Pijat 90 Menit ke Rumah — Rp60.000 ditambah biaya perjalanan.
- Pijat 2 Jam ke Rumah — Rp80.000 ditambah biaya perjalanan.
- Pijat 2 Orang ke Rumah — 90 menit, Rp120.000 ditambah biaya perjalanan.

Jam layanan: 08.00–15.00 dan 19.00–24.00. Untuk layanan ke Rumah, lokasi tujuan digunakan untuk menghitung jarak jalan. 1.000 meter pertama gratis; selebihnya Rp3,50 per meter. Biaya perjalanan dihitung satu kali per booking.

Aplikasi digunakan untuk mengajukan dan memantau booking; aplikasi tidak menyediakan checkout atau pembayaran online.

## Aset visual

Aset siap unggah disiapkan dari UI production dan ikon resmi yang sudah ada. Screenshot diambil pada 1080×1920 dari situs production pada viewport ponsel 432×768, dengan mode tampilan standalone disimulasikan agar tombol instal web tidak muncul. Screenshot bukan hasil tangkapan dari perangkat Android yang telah memasang AAB; periksa tampilan akhir di perangkat sebelum publikasi.

- `01-beranda.png` — Beranda production.
- `02-katalog.png` — Katalog dan paket/harga production.
- `feature-graphic.png` — 1024×500, memakai logo dan screenshot UI production.
- `app-icon-512.png` — ikon PWA existing 512×512; tidak dibuat ulang.

Aset berada dalam paket lokal `sules-google-play-materials.zip`. Google Play dapat meminta screenshot tambahan berdasarkan jenis perangkat yang dipilih pada Console.

## Draf Data Safety berbasis source

| Data yang tampak dikumpulkan/diproses | Tujuan nyata pada aplikasi | Catatan pengisian |
|---|---|---|
| Email akun | Masuk/daftar melalui Supabase Auth OTP dan mengaitkan akun dengan booking. | Kategori Personal info → Email address; digunakan untuk Account management dan App functionality. Email diteruskan ke penyedia pengiriman email untuk OTP. |
| Nama dan nomor WhatsApp | Profil pelanggan serta komunikasi/pemenuhan layanan. | Kategori Personal info → Name dan Phone number; digunakan untuk Account management dan App functionality. |
| Detail booking (paket/layanan, jumlah orang, tanggal, waktu, lokasi layanan, status; alamat bila diberikan) | Membuat, memproses, menampilkan, dan mengelola booking. | Terikat ke akun; petakan ke kategori Console yang paling sesuai, termasuk Other personal info bila Console mengklasifikasikannya demikian. Tidak ada pembayaran kartu di aplikasi. |
| Lokasi presisi (koordinat) | Fitur Lokasi akurat untuk layanan ke Rumah dan penghitungan jarak jalan/biaya perjalanan. | Kategori Location → Precise location. Data dikirim ke Supabase; koordinat tujuan diteruskan melalui proxy ke Google Routes untuk menghitung jarak jalan. Penggunaan hanya relevan saat pelanggan memilih layanan ke Rumah dan memberikan lokasi. |

**Data Safety tidak boleh diisi sebagai “tidak mengumpulkan data”.** Pengiriman email OTP memakai Supabase Auth/Resend; profil dan booking disimpan pada Supabase; koordinat untuk penghitungan rute diproses Google Routes. Tinjau syarat dan peran pemroses masing-masing penyedia sebelum menjawab pertanyaan “data sharing”; jangan menyatakan “tidak dibagikan” hanya berdasarkan source frontend.

Source menggunakan HTTPS untuk production dan koneksi API. Sebelum menjawab bahwa *semua* data dienkripsi saat transit, pastikan konfigurasi transport setiap jalur layanan termasuk email/SMTP. Kebijakan privasi belum menetapkan jangka retensi numerik; pemilik harus menetapkan jawaban sesuai praktik operasional. Tidak terlihat input pembayaran kartu atau Google Play Billing. Tidak terlihat SDK iklan/analitik pada wrapper yang diperiksa; pemilik tetap perlu mengonfirmasi seluruh layanan/proyek terkait.

Penghapusan: aplikasi menyediakan **Akun → Hapus Akun**; fungsi server hanya memakai user dari sesi terautentikasi, menghapus Auth user, dan cascade menghapus profil serta booking yang terkait. Uji deletion akun QA production sebelumnya berhasil. Pengguna yang tidak dapat masuk dapat meminta penghapusan lewat resource web/email di atas. Jangan menjanjikan jangka proses yang belum ditetapkan.

## Pemeriksaan Android release

- Package `com.bookingpijat.sules`, version name `1.0.0`, version code `2`, target SDK `36`.
- Permission yang tercantum di APK: `ACCESS_FINE_LOCATION` dan `ACCESS_COARSE_LOCATION` untuk lokasi akurat; `com.bookingpijat.sules.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` adalah permission library AndroidX untuk receiver dinamis non-exported. Tidak tercantum `POST_NOTIFICATIONS` atau `BILLING`.
- Upload keystore berada di luar file yang dilacak Git; jangan unggah atau kirim private key/password.
- `https://bookingpijat.com/.well-known/assetlinks.json` saat terakhir diperiksa memberi HTTP 404. Ini tidak menghalangi upload AAB, tetapi TWA belum dapat membuktikan hubungan domain untuk tampilan penuh tanpa UI tab browser. Setelah app dibuat dan Play App Signing dipilih, ambil SHA-256 **App signing key certificate** dari Play Console, lalu terbitkan Digital Asset Links yang cocok sebelum rilis publik. Jangan memakai fingerprint upload key secara asumsi.

## Yang tetap perlu dilakukan pemilik di Play Console

1. Buat/pilih aplikasi, pastikan `com.bookingpijat.sules` tersedia, lalu unggah `app-release-bundle.aab`.
2. Tinjau pilihan Play App Signing. Setelah sertifikat app-signing tersedia, siapkan `assetlinks.json` untuk domain production sebelum rilis TWA penuh.
3. Isi kategori dan negara distribusi; selesaikan Data Safety berdasarkan praktik Supabase, Resend, Google Routes, serta keputusan retensi yang benar.
4. Isi target audiens, klasifikasi konten/IARC, iklan, akses reviewer (aplikasi memakai OTP email), harga/gratis, dan kontak developer. Jangan berikan akun Admin untuk review; jika akses dibatasi, siapkan jalur akun uji/reviewer yang aman.
5. Unggah ikon, feature graphic, dan screenshot; tinjau screenshot pada perangkat Android nyata. Selesaikan closed testing jika Play Console mewajibkannya untuk jenis akun developer tersebut.
6. Tinjau preview listing/Data Safety lalu submit untuk review. Aset dan metadata belum dikirim ke Play Console oleh sesi ini.

## Referensi kebijakan resmi

- [Account deletion](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en) — aplikasi dengan pembuatan akun harus menyediakan jalur hapus akun di aplikasi dan web resource untuk permintaan penghapusan akun/data terkait.
- [Data Safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en) — deklarasi harus mencakup aplikasi dan pemrosesan pihak ketiga; pengembang bertanggung jawab atas keakuratan.
- [Preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en) — panduan screenshot dan grafis listing.
- [Categories and tags](https://support.google.com/googleplay/android-developer/answer/9859673?hl=en) — pilih kategori/tag yang jelas relevan.
- [Target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en) — untuk aplikasi baru/updates sejak 31 Agustus 2026, target Android 16/API 36 atau lebih tinggi, dengan pengecualian platform yang dinyatakan Google.
