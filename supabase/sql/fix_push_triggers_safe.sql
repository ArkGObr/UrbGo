-- ═══════════════════════════════════════════════════════════════
-- FIX: Torna os triggers de push tolerantes a falta de configuração
-- Execute no Supabase SQL Editor
--
-- Problema: current_setting('app.supabase_url') lança exceção quando
-- a variável não foi configurada, bloqueando INSERT/UPDATE/DELETE.
-- Solução: usar missing_ok=true + checar se o valor existe antes de
-- tentar enviar o push. Operações no banco nunca são bloqueadas.
-- ═══════════════════════════════════════════════════════════════

-- ── Helper: tenta enviar push; silencia qualquer erro ──────────
CREATE OR REPLACE FUNCTION public.arkgo_send_push(
  p_token TEXT,
  p_title TEXT,
  p_body  TEXT,
  p_data  JSONB DEFAULT '{}'::JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_url  TEXT;
  v_key  TEXT;
BEGIN
  -- Sai silenciosamente se token vazio
  IF p_token IS NULL OR p_token = '' THEN
    RETURN;
  END IF;

  -- missing_ok = true → retorna NULL em vez de lançar exceção
  v_url := current_setting('app.supabase_url', true);
  v_key := current_setting('app.service_role_key', true);

  -- Sai silenciosamente se as variáveis ainda não foram configuradas
  IF v_url IS NULL OR v_url = '' OR v_key IS NULL OR v_key = '' THEN
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body    := jsonb_build_object(
      'token', p_token,
      'title', p_title,
      'body',  p_body,
      'data',  p_data
    )
  );

EXCEPTION WHEN OTHERS THEN
  -- Nunca deixa o push bloquear a operação principal
  NULL;
END;
$$;


-- ── Trigger 1: nova entrega → notificar motoboys ───────────────
CREATE OR REPLACE FUNCTION public.notify_motoboys_new_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r       RECORD;
  net_val NUMERIC;
BEGIN
  BEGIN
    net_val := ROUND((NEW.value - NEW.commission)::NUMERIC, 2);

    FOR r IN
      SELECT u.fcm_token
      FROM motoboys m
      JOIN users u ON u.id = m.id
      WHERE m.is_online = true
        AND u.fcm_token IS NOT NULL
        AND m.vehicle_category = NEW.vehicle_category
      LIMIT 50
    LOOP
      PERFORM public.arkgo_send_push(
        r.fcm_token,
        'Nova corrida disponível!',
        'Você recebe R$ ' || net_val::TEXT || ' — Aceite rápido!',
        jsonb_build_object(
          'deliveryId', NEW.id::TEXT,
          'role',       'motoboy',
          'type',       'new_delivery'
        )
      );
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    NULL; -- push nunca bloqueia criação de entrega
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_new_delivery ON public.deliveries;
CREATE TRIGGER trg_notify_new_delivery
  AFTER INSERT ON public.deliveries
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_motoboys_new_delivery();


-- ── Trigger 2: mudança de status → notificar cliente/motoboy ───
CREATE OR REPLACE FUNCTION public.notify_delivery_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_client_token  TEXT;
  v_motoboy_token TEXT;
  v_motoboy_name  TEXT;
  v_net_val       NUMERIC;
BEGIN
  -- Garante que a operação principal nunca é bloqueada
  BEGIN
    IF OLD.status = NEW.status THEN
      RETURN NEW;
    END IF;

    SELECT fcm_token INTO v_client_token
    FROM users WHERE id = NEW.client_id;

    IF NEW.motoboy_id IS NOT NULL THEN
      SELECT u.fcm_token, u.name
      INTO   v_motoboy_token, v_motoboy_name
      FROM   users u WHERE u.id = NEW.motoboy_id;
    END IF;

    v_net_val := ROUND((NEW.value - NEW.commission)::NUMERIC, 2);

    IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
      PERFORM public.arkgo_send_push(
        v_client_token,
        'Entregador a caminho!',
        COALESCE(v_motoboy_name, 'Seu entregador') || ' aceitou o pedido.',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'accepted')
      );

    ELSIF NEW.status = 'in_progress' AND OLD.status = 'accepted' THEN
      PERFORM public.arkgo_send_push(
        v_client_token,
        'Pacote coletado!',
        'Seu pedido está a caminho do destino.',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'in_progress')
      );

    ELSIF NEW.status = 'completed' AND OLD.status = 'in_progress' THEN
      PERFORM public.arkgo_send_push(
        v_client_token,
        'Entrega concluída! ✓',
        'Seu pedido chegou com sucesso. Avalie seu entregador!',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'completed')
      );
      PERFORM public.arkgo_send_push(
        v_motoboy_token,
        'Corrida finalizada!',
        'Você ganhou R$ ' || v_net_val::TEXT || ' nesta entrega.',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'motoboy', 'type', 'run_completed')
      );

    ELSIF NEW.status = 'cancelled' THEN
      PERFORM public.arkgo_send_push(
        v_client_token,
        'Entrega cancelada',
        'Sua entrega foi cancelada.',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'cancelled')
      );
      IF v_motoboy_token IS NOT NULL THEN
        PERFORM public.arkgo_send_push(
          v_motoboy_token,
          'Corrida cancelada',
          'A entrega foi cancelada pelo cliente.',
          jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'motoboy', 'type', 'run_cancelled')
        );
      END IF;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    NULL; -- push nunca bloqueia mudança de status
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_delivery_status ON public.deliveries;
CREATE TRIGGER trg_notify_delivery_status
  AFTER UPDATE ON public.deliveries
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_delivery_status_change();


-- ── Trigger 3: recarga confirmada → notificar motoboy ──────────
CREATE OR REPLACE FUNCTION public.notify_motoboy_recharge()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_token TEXT;
BEGIN
  BEGIN
    IF NEW.gateway_status <> 'confirmed' OR OLD.gateway_status = 'confirmed' THEN
      RETURN NEW;
    END IF;

    SELECT u.fcm_token INTO v_token
    FROM users u WHERE u.id = NEW.motoboy_id;

    PERFORM public.arkgo_send_push(
      v_token,
      'Saldo recarregado!',
      'R$ ' || ROUND(NEW.amount::NUMERIC, 2)::TEXT || ' adicionados à sua carteira.',
      jsonb_build_object('role', 'motoboy', 'type', 'recharge', 'amount', NEW.amount::TEXT)
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_recharge ON public.recharges;
CREATE TRIGGER trg_notify_recharge
  AFTER UPDATE ON public.recharges
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_motoboy_recharge();
