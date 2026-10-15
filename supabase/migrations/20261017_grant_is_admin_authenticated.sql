-- Perbaikan: "permission denied for function is_admin"
--
-- Penyebab: kebijakan RLS package_pricing_admin_update (role authenticated)
-- memanggil public.is_admin() pada USING dan WITH CHECK, tetapi role
-- authenticated tidak punya EXECUTE pada fungsi itu (hanya postgres dan
-- service_role). Fungsi RPC SECURITY DEFINER lain tidak terpengaruh karena
-- berjalan sebagai owner (postgres).
--
-- Keamanan: is_admin() SECURITY DEFINER, search_path dikunci ke public, hanya
-- mengembalikan boolean untuk auth.uid() pemanggil sendiri (tidak membocorkan
-- data admins). anon dan PUBLIC TIDAK diberi izin.
--
-- Idempoten: aman dijalankan berulang.

revoke all on function public.is_admin() from public;
revoke all on function public.is_admin() from anon;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_admin() to service_role;
