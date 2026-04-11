-- ══════════════════════════════════════════════════════════════
-- Desabilitar triggers de push notification temporariamente
-- O trigger usa net.http_post() que requer a extensão pg_net.
-- Execute no Supabase SQL Editor até configurar push.
-- ══════════════════════════════════════════════════════════════

-- Remove o trigger que bloqueia INSERT em deliveries
DROP TRIGGER IF EXISTS trg_notify_new_delivery ON public.deliveries;

-- Remove o trigger de status update (também usa net.http_post)
DROP TRIGGER IF EXISTS trg_notify_delivery_status ON public.deliveries;

-- As funções podem ficar, não causam problema sem o trigger.
-- Quando quiser reativar:
--   1. Habilite pg_net em Database → Extensions
--   2. Configure app.supabase_url e app.service_role_key
--   3. Recrie os triggers com:
--      CREATE TRIGGER trg_notify_new_delivery
--        AFTER INSERT ON public.deliveries
--        FOR EACH ROW EXECUTE FUNCTION public.notify_motoboys_new_delivery();
--      CREATE TRIGGER trg_notify_delivery_status
--        AFTER UPDATE ON public.deliveries
--        FOR EACH ROW EXECUTE FUNCTION public.notify_client_delivery_status();
