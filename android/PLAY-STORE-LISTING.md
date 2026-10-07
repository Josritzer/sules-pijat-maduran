# Draf Google Play listing — SULES PIJAT MADURAN

Dokumen ini memakai fakta yang sudah dipublikasikan website. Nilai di bagian “perlu keputusan/verifikasi pemilik” sengaja tidak dikarang.

## Metadata yang dapat disiapkan

| Field | Nilai draf | Sumber |
|---|---|---|
| Nama di Play Store | SULES PIJAT MADURAN | `<title>` website |
| Nama Android | Sules Relaxing Massage | `manifest.webmanifest` |
| Short name launcher | Sules | `manifest.webmanifest` |
| Package ID | `com.bookingpijat.sules` | TWA project; pastikan tersedia saat membuat app di Play Console |
| Deskripsi pendek | Booking pijat Sules Maduran: pilih 1 dari 5 paket dan jadwalkan layanan. | Diringkas dari meta description; 72 karakter |
| Deskripsi lengkap (draf) | SULES PIJAT MADURAN menyediakan booking pijat di area Maduran, Lamongan. Pilih satu dari lima paket layanan yang tersedia, pilih layanan di Sules atau ke Rumah, tentukan tanggal dan waktu, lalu pantau status booking melalui akun pelanggan. Jam layanan: 08.00–15.00 dan 19.00–24.00. | Website production dan source saat ini |
| Kebijakan privasi | https://bookingpijat.com/#kebijakan-privasi | Halaman produksi |
| Email kontak | srawungjagad3714@gmail.com | Link kontak publik di website |
| WhatsApp kontak | https://wa.me/6285855603240 | Link kontak publik di website |
| Ikon aplikasi | https://bookingpijat.com/icons/pwa-512.png | Ikon 512×512 di manifest |
| Website | https://bookingpijat.com/ | Origin production canonical saat diperiksa |

## Field Console yang tetap harus diisi/ditinjau pemilik

- Kategori aplikasi, negara distribusi, bahasa, target audiens/usia, klasifikasi konten, dan pernyataan rating.
- Data safety: tinjau pengumpulan/pemrosesan email OTP, nama, WhatsApp, detail booking, serta koordinat lokasi yang pelanggan pilih untuk fitur Lokasi akurat. Pastikan jawaban berbagi, tujuan, retensi, keamanan, dan penghapusan cocok dengan kebijakan serta praktik aktual. Jangan menyatakan “tidak mengumpulkan/berbagi data” tanpa verifikasi.
- Screenshot ponsel/tablet dan feature graphic harus diambil/dibuat untuk listing setelah aplikasi diuji pada perangkat; jangan mengklaim screenshot browser sebagai screenshot aplikasi terpasang.
- Konfirmasi `com.bookingpijat.sules` masih tersedia saat app dibuat. Package ID tidak dapat dipesan/dipastikan hanya dari file lokal.

## Persiapan Digital Asset Links

Production canonical yang diperiksa adalah `https://bookingpijat.com/`; host `www` mengalihkan ke non-`www`. Saat pemeriksaan, `https://bookingpijat.com/.well-known/assetlinks.json` mengembalikan HTTP 404. Jangan menerbitkan fingerprint upload key sebagai app-signing fingerprint Play tanpa memastikan strategi Play App Signing. Setelah app dibuat, ambil SHA-256 sertifikat **App signing key certificate** dari Play Console dan siapkan file `/.well-known/assetlinks.json` untuk domain canonical; file ini belum diterbitkan.

## Blocker utama sebelum Play release

Source aplikasi saat ini mengizinkan pembuatan akun customer tetapi tidak menyediakan jalur penghapusan akun di dalam aplikasi. Kebijakan Google Play mensyaratkan jalur penghapusan di dalam aplikasi bagi aplikasi yang memungkinkan pembuatan akun, serta resource web untuk permintaan penghapusan. Lengkapi dan uji alur tersebut sebelum menyatakan listing siap rilis; perubahan itu tidak termasuk pekerjaan wrapper ini.
