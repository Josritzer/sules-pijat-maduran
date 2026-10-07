# SULES Android wrapper (Trusted Web Activity)

Ini adalah wrapper Android untuk PWA Sules yang sudah ada, bukan aplikasi atau backend baru. Website tetap menjadi aplikasi utama dan tetap dilayani dari `https://bookingpijat.com/`.

## Konfigurasi

- Application ID: `com.bookingpijat.sules`
- App name: `Sules Relaxing Massage`; launcher name: `Sules`
- Version name/code awal: `1.0.0` / `1`
- TWA origin/start path: `https://bookingpijat.com/`
- Manifest: `https://bookingpijat.com/manifest.webmanifest`
- Ikon: ikon PWA Sules 512×512 yang sudah ada
- Compile/target SDK: 36
- `locationDelegation`: aktif untuk fitur GPS/Lokasi akurat booking yang sudah ada
- Push-notification delegation dan `POST_NOTIFICATIONS`: nonaktif karena source web tidak menggunakan Web Push
- Tidak ditambahkan SMS, Contacts, Phone, Storage, Camera, atau Microphone permission

## Build release

Memerlukan JDK 17, Android SDK Platform/Build Tools API 36, dan Bubblewrap CLI 1.25.0. Dari direktori ini, jalankan `npx --yes @bubblewrap/cli@1.25.0 build`. Set `BUBBLEWRAP_KEYSTORE_PASSWORD` dan `BUBBLEWRAP_KEY_PASSWORD` melalui secret manager/environment privat, jangan masukkan nilai rahasia ke terminal yang direkam atau Git. Hasil release berada di `app/build/outputs/`.

`upload-key.jks` adalah signing upload key lokal dan di-ignore Git. Simpan keystore dan recovery credential note secara terpisah di tempat aman; kehilangan upload key dapat menghambat update berikutnya. Jangan commit atau kirimkannya melalui repo publik.

## Sebelum Play release

- App Links/TWA belum menjadi fully verified: `https://bookingpijat.com/.well-known/assetlinks.json` belum tersedia pada pemeriksaan build ini. Setelah aplikasi dibuat di Play Console, gunakan SHA-256 **App signing key certificate** dari Console untuk membuat dan menerbitkan Digital Asset Links di domain canonical. Jangan menebak fingerprint.
- Isi dan tinjau data safety, target audience, kategori, rating konten, distribusi, listing image/screenshot, dan kontak di Play Console berdasarkan praktik aktual.
- Blocker utama kebijakan: aplikasi saat ini tidak menyediakan jalur penghapusan akun di dalam aplikasi. Selesaikan persyaratan penghapusan akun Google Play sebelum menyatakan rilis siap.

Build ini tidak mengubah `index.html`, alur booking, Auth, Supabase, database, atau konfigurasi production website.
