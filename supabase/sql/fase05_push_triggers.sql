-- ═══════════════════════════════════════════════════════════
-- FASE 05 — Triggers de Push Notification
-- Execute no Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════
--
-- ANTES de executar, configure os settings do banco:
-- ALTER DATABASE postgres SET "app.supabase_url" = 'https://SEU_PROJETO.supabase.co';
-- ALTER DATABASE postgres SET "app.service_role_key" = 'sua_service_role_key';
--
-- E faça deploy da Edge Function:
-- supabase functions deploy send-push
-- supabase secrets set FCM_SERVER_KEY=sua_server_key_do_firebase
-- ═══════════════════════════════════════════════════════════

-- ── 1. Notificar motoboys online quando nova entrega é criada ──
CREATE OR REPLACE FUNCTION public.notify_motoboys_new_delivery()
RETURNS TRIGGER AS $$
DECLARE
  motoboy_tokens TEXT[];
  token TEXT;
BEGIN
  -- Buscar tokens FCM dos motoboys online
  SELECT ARRAY_AGG(u.fcm_token)
  INTO motoboy_tokens
  FROM motoboys m
  JOIN users u ON u.id = m.id
  WHERE m.is_online = true
    AND u.fcm_token IS NOT NULL;

  -- Disparar push para cada motoboy (máx 50 no MVP)
  IF motoboy_tokens IS NOT NULL THEN
    FOREACH token IN ARRAY motoboy_tokens[1:50] LOOP
      PERFORM net.http_post(
        url     := current_setting('app.supabase_url') || '/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || current_setting('app.service_role_key')
        ),
        body := jsonb_build_object(
          'token', token,
          'title', 'Nova corrida disponível!',
          'body',  'Uma entrega perto de você está esperando.',
          'data',  jsonb_build_object('deliveryId', NEW.id::text, 'role', 'motoboy')
        )
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_new_delivery ON public.deliveries;
CREATE TRIGGER trg_notify_new_delivery
  AFTER INSERT ON public.deliveries
  FOR EACH ROW EXECUTE FUNCTION public.notify_motoboys_new_delivery();

-- ── 2. Notificar cliente quando motoboy aceita ou finaliza ────
CREATE OR REPLACE FUNCTION public.notify_client_delivery_status()
RETURNS TRIGGER AS $$
DECLARE
  client_token TEXT;
  motoboy_name TEXT;
BEGIN
  -- Motoboy aceitou a corrida
  IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
    SELECT u.fcm_token INTO client_token
    FROM users u WHERE u.id = NEW.client_id;

    SELECT u.name INTO motoboy_name
    FROM users u WHERE u.id = NEW.motoboy_id;

    IF client_token IS NOT NULL THEN
      PERFORM net.http_post(
        url     := current_setting('app.supabase_url') || '/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || current_setting('app.service_role_key')
        ),
        body := jsonb_build_object(
          'token', client_token,
          'title', 'Motoboy a caminho!',
          'body',  motoboy_name || ' aceitou sua entrega.',
          'data',  jsonb_build_object('deliveryId', NEW.id::text, 'role', 'client')
        )
      );
    END IF;
  END IF;

  -- Entrega concluída
  IF NEW.status = 'completed' AND OLD.status = 'in_progress' THEN
    SELECT u.fcm_token INTO client_token
    FROM users u WHERE u.id = NEW.client_id;

    IF client_token IS NOT NULL THEN
      PERFORM net.http_post(
        url     := current_setting('app.supabase_url') || '/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || current_setting('app.service_role_key')
        ),
        body := jsonb_build_object(
          'token', client_token,
          'title', 'Entrega realizada! ✓',
          'body',  'Seu pedido foi entregue com sucesso.',
          'data',  jsonb_build_object('deliveryId', NEW.id::text, 'role', 'client')
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_delivery_status ON public.deliveries;
CREATE TRIGGER trg_notify_delivery_status
  AFTER UPDATE ON public.deliveries
  FOR EACH ROW EXECUTE FUNCTION public.notify_client_delivery_status();
