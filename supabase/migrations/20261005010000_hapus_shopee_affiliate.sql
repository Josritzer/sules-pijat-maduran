-- Sules V1: fitur Shopee Affiliate dihapus seluruhnya.
-- PERINGATAN: menghapus permanen data link/produk Shopee. Booking, customer, dan data lain tidak disentuh.
-- Jalankan HANYA setelah index.html versi tanpa Shopee sudah dipasang.
BEGIN;

DROP FUNCTION IF EXISTS public.admin_get_shopee_affiliate_slots();
DROP FUNCTION IF EXISTS public.admin_save_shopee_affiliate_slot(smallint, text, text, text, text, text, boolean);
DROP FUNCTION IF EXISTS public.admin_get_shopee_affiliate_links();
DROP FUNCTION IF EXISTS public.admin_save_shopee_affiliate_link(smallint, text, boolean);
DROP FUNCTION IF EXISTS public.get_active_shopee_affiliate_links();
DROP FUNCTION IF EXISTS public.admin_save_shopee_product_slot(smallint, text, text, numeric, text, boolean);
DROP FUNCTION IF EXISTS public.get_active_shopee_product_cards();
DROP FUNCTION IF EXISTS public.admin_get_shopee_product_slots_v2();
DROP FUNCTION IF EXISTS public.admin_save_shopee_product_slot_v2(smallint, text, text, numeric, numeric, text, boolean);
DROP FUNCTION IF EXISTS public.get_active_shopee_product_cards_v2();

DROP TABLE IF EXISTS public.shopee_affiliate_slots;

NOTIFY pgrst, 'reload schema';
COMMIT;
