-- Cabut hak tabel UPDATE dari role anon pada public.package_pricing_config.
--
-- Alasan: anon tidak punya kebutuhan menulis konfigurasi harga. Saat ini UPDATE
-- anon sudah tertahan RLS (tidak ada policy UPDATE untuk anon), tetapi hak
-- tabelnya tidak perlu ada (defense in depth).
--
-- Tidak diubah: SELECT publik (policy package_pricing_public_read), policy RLS,
-- hak authenticated/service_role, akses admin (package_pricing_admin_update),
-- struktur tabel, harga, dan logika booking.
--
-- Idempoten: REVOKE pada hak yang sudah tidak ada tidak menimbulkan error.

revoke update on table public.package_pricing_config from anon;
