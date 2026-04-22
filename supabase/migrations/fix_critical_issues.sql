-- ============================================================
-- Correções críticas:
--   1. RPC abandon_delivery  — motoboy desiste de corrida aceita
--   2. pg_cron: cancelar corridas 'pending' sem aceitação em 30 min
-- ============================================================

-- 1. Função RPC: abandon_delivery
-- Segurança: só funciona se o motoboy logado é o dono da corrida
CREATE OR REPLACE FUNCTION public.abandon_delivery(p_delivery_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE deliveries
  SET
    status      = 'pending',
    motoboy_id  = NULL,
    accepted_at = NULL
  WHERE id        = p_delivery_id
    AND status    = 'accepted'
    AND motoboy_id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não foi possível desistir. Corrida não encontrada ou já em andamento.';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.abandon_delivery(UUID) TO authenticated;

-- 2. Cancelar corridas 'pending' sem aceite após 30 minutos
-- Isso evita corridas fantasma no mapa e notificações infinitas
CREATE OR REPLACE FUNCTION public.cancel_stale_pending_deliveries()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE deliveries
  SET status = 'cancelled'
  WHERE status     = 'pending'
    AND created_at < NOW() - INTERVAL '30 minutes';
END;
$$;

-- Agendar via pg_cron a cada 5 minutos
SELECT cron.schedule(
  'cancel-stale-pending-deliveries',
  '*/5 * * * *',
  'SELECT public.cancel_stale_pending_deliveries()'
);
