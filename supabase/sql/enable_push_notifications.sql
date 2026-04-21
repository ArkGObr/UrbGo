-- ═══════════════════════════════════════════════════════════════════════
-- PUSH NOTIFICATIONS — Ativação completa
-- ═══════════════════════════════════════════════════════════════════════
--
-- PRÉ-REQUISITOS (execute uma única vez no Supabase Dashboard):
--
--   1. Database → Extensions → habilitar "pg_net"
--
--   2. SQL Editor — configurar variáveis de ambiente do banco:
--      ALTER DATABASE postgres SET "app.supabase_url"      = 'https://SEU_PROJETO.supabase.co';
--      ALTER DATABASE postgres SET "app.service_role_key"  = 'sua_service_role_key';
--
--   3. Deploy da Edge Function (terminal):
--      supabase functions deploy send-push
--      supabase secrets set FCM_SERVER_KEY=sua_server_key_do_firebase
--
-- Depois execute este arquivo inteiro no SQL Editor.
-- ═══════════════════════════════════════════════════════════════════════


-- ── Helper: envia push para um único token ──────────────────────────────
CREATE OR REPLACE FUNCTION public.urbgo_send_push(
  p_token TEXT,
  p_title TEXT,
  p_body  TEXT,
  p_data  JSONB DEFAULT '{}'::JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_token IS NULL OR p_token = '' THEN
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := current_setting('app.supabase_url') || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || current_setting('app.service_role_key')
    ),
    body    := jsonb_build_object(
      'token', p_token,
      'title', p_title,
      'body',  p_body,
      'data',  p_data
    )
  );
END;
$$;


-- ══════════════════════════════════════════════════════════════════════
-- TRIGGER 1 — Nova entrega criada → notificar motoboys online
--             Filtra pela mesma categoria de veículo
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.notify_motoboys_new_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r       RECORD;
  net_val NUMERIC;
BEGIN
  -- Valor líquido para o motoboy
  net_val := ROUND((NEW.value - NEW.commission)::NUMERIC, 2);

  FOR r IN
    SELECT u.fcm_token
    FROM motoboys m
    JOIN users u ON u.id = m.id
    WHERE m.is_online = true
      AND u.fcm_token IS NOT NULL
      AND m.vehicle_category = NEW.vehicle_category
    LIMIT 50                            -- limite de segurança no MVP
  LOOP
    PERFORM public.urbgo_send_push(
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

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_new_delivery ON public.deliveries;
CREATE TRIGGER trg_notify_new_delivery
  AFTER INSERT ON public.deliveries
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_motoboys_new_delivery();


-- ══════════════════════════════════════════════════════════════════════
-- TRIGGER 2 — Mudança de status → notificar cliente e/ou motoboy
-- ══════════════════════════════════════════════════════════════════════
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
  -- Só dispara quando o status realmente muda
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Busca tokens
  SELECT fcm_token INTO v_client_token
  FROM users WHERE id = NEW.client_id;

  IF NEW.motoboy_id IS NOT NULL THEN
    SELECT u.fcm_token, u.name
    INTO   v_motoboy_token, v_motoboy_name
    FROM   users u WHERE u.id = NEW.motoboy_id;
  END IF;

  v_net_val := ROUND((NEW.value - NEW.commission)::NUMERIC, 2);

  -- ── pending → accepted ─────────────────────────────────────────────
  IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN

    -- Cliente: motoboy aceitou
    PERFORM public.urbgo_send_push(
      v_client_token,
      'Entregador a caminho!',
      COALESCE(v_motoboy_name, 'Seu entregador') || ' aceitou o pedido e está indo buscar o pacote.',
      jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'accepted')
    );

  -- ── accepted → in_progress ─────────────────────────────────────────
  ELSIF NEW.status = 'in_progress' AND OLD.status = 'accepted' THEN

    -- Cliente: pacote coletado
    PERFORM public.urbgo_send_push(
      v_client_token,
      'Pacote coletado!',
      'Seu pedido foi retirado e está a caminho do destino.',
      jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'in_progress')
    );

  -- ── in_progress → completed ────────────────────────────────────────
  ELSIF NEW.status = 'completed' AND OLD.status = 'in_progress' THEN

    -- Cliente: entrega concluída
    PERFORM public.urbgo_send_push(
      v_client_token,
      'Entrega concluída! ✓',
      'Seu pedido chegou com sucesso. Avalie seu entregador!',
      jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'completed')
    );

    -- Motoboy: corrida finalizada com ganho
    PERFORM public.urbgo_send_push(
      v_motoboy_token,
      'Corrida finalizada!',
      'Você ganhou R$ ' || v_net_val::TEXT || ' nesta entrega.',
      jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'motoboy', 'type', 'run_completed')
    );

  -- ── qualquer → cancelled ───────────────────────────────────────────
  ELSIF NEW.status = 'cancelled' THEN

    -- Cliente: cancelado
    PERFORM public.urbgo_send_push(
      v_client_token,
      'Entrega cancelada',
      'Sua entrega foi cancelada. Entre em contato com o suporte se precisar de ajuda.',
      jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'cancelled')
    );

    -- Motoboy (se havia um atribuído): notifica também
    IF v_motoboy_token IS NOT NULL THEN
      PERFORM public.urbgo_send_push(
        v_motoboy_token,
        'Corrida cancelada',
        'A entrega foi cancelada pelo cliente.',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'motoboy', 'type', 'run_cancelled')
      );
    END IF;

  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_delivery_status ON public.deliveries;
CREATE TRIGGER trg_notify_delivery_status
  AFTER UPDATE ON public.deliveries
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_delivery_status_change();


-- ══════════════════════════════════════════════════════════════════════
-- TRIGGER 3 — Recarga confirmada no banco → notificar motoboy
--             (complementa o webhook Asaas que já envia via Edge Function)
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.notify_motoboy_recharge()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_token TEXT;
BEGIN
  -- Só dispara quando gateway_status muda para 'confirmed'
  IF NEW.gateway_status <> 'confirmed' OR OLD.gateway_status = 'confirmed' THEN
    RETURN NEW;
  END IF;

  SELECT u.fcm_token INTO v_token
  FROM users u WHERE u.id = NEW.motoboy_id;

  PERFORM public.urbgo_send_push(
    v_token,
    'Saldo recarregado!',
    'R$ ' || ROUND(NEW.amount::NUMERIC, 2)::TEXT || ' foram adicionados à sua carteira.',
    jsonb_build_object(
      'role', 'motoboy',
      'type', 'recharge',
      'amount', NEW.amount::TEXT
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_recharge ON public.recharges;
CREATE TRIGGER trg_notify_recharge
  AFTER UPDATE ON public.recharges
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_motoboy_recharge();
