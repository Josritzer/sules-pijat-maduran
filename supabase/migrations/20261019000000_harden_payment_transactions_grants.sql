-- Keep payment ledger inaccessible to public API roles.
-- Payment reads/writes must pass through authenticated Edge Functions using service_role.
revoke all privileges on table public.payment_transactions from anon, authenticated;
grant all privileges on table public.payment_transactions to service_role;
