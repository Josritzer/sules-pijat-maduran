# Android Release — SL Relax

## Identitas aplikasi

- Nama aplikasi: **SL Relax**
- Label launcher: **SL**
- Application ID: `com.bookingpijat.sules`
- TWA launch URL: `https://bookingpijat.com/`
- Version name: `1.0.0`
- Version code pada source saat ini: `3` — **belum dikonfirmasi tersedia di Google Play Console**. Pastikan sebelum release; jika sudah pernah dipakai, naikkan version code di `app/build.gradle` dan `twa-manifest.json` ke angka berikutnya yang belum digunakan.

## Signing yang aman

Source memakai keystore existing di `android/upload-key.jks` dan alias `sulesupload` dari `twa-manifest.json`. File keystore diabaikan Git. Jangan menambah keystore atau password ke repository, Gradle files, command-line arguments, atau chat.

Gradle mengambil password hanya dari environment build:

- `SULES_UPLOAD_STORE_PASSWORD`
- `SULES_UPLOAD_KEY_PASSWORD`

Jika salah satu tidak tersedia, file keystore tidak ada, alias tidak dapat dibaca, atau sertifikat tidak cocok, task `bundleRelease`/`assembleRelease` akan berhenti sebelum menghasilkan artefak release. Signing guard memeriksa SHA-256 certificate lama:

`73:5B:7E:AB:D0:C7:DD:F5:40:C0:94:52:61:56:A5:B3:A1:10:B7:A7:15:93:E1:96:87:E8:49:E1:BC:B0:97:1F`

Jangan membuat atau mengganti kunci. Saat kredensial tersedia, masukkan kedua secret melalui environment/secret manager lokal atau CI yang tepercaya; jangan menuliskan nilainya ke file source.

## Build dan verifikasi (setelah prasyarat tersedia)

1. Pastikan version code yang dipilih belum pernah digunakan di Play Console.
2. Pastikan alias keystore lama lolos pemeriksaan fingerprint.
3. Jalankan `./gradlew bundleRelease` dari direktori `android/` dengan dua environment variable di atas tersedia.
4. Artefak yang diharapkan: `android/app/build/outputs/bundle/release/app-release.aab`.
5. Verifikasi package, version name/code melalui Bundletool; verifikasi signature dengan `jarsigner -verify`. Jangan menyebut bundle siap unggah sebelum keduanya lulus.

Build debug dapat dijalankan tanpa signing secrets dengan `./gradlew assembleDebug`.

## Konten Paket 5

Aplikasi adalah Trusted Web Activity yang membuka situs production; katalog dan flow Paket 5 disajikan oleh website, bukan disalin ke AAB. Perubahan website production tidak memerlukan rebuild wrapper. Verifikasi production terakhir menemukan Paket 5 180 menit total (90+90 berurutan), Rp120.000, dengan biaya perjalanan satu kali per booking.

## Status persiapan

Version code `3` menunggu pemeriksaan Play Console. Keystore tersedia secara lokal, tetapi kredensial signing belum tersedia di konfigurasi environment saat ini. Sampai kedua prasyarat tersebut terpenuhi dan AAB signed diverifikasi, source ini **belum menghasilkan AAB release siap unggah**.
