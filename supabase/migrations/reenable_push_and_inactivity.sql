-- ═══════════════════════════════════════════════════════════════════════════
-- PRÉ-REQUISITOS (execute uma única vez no Supabase Dashboard se ainda não fez)
--
-- 1. Database → Extensions → habilitar "pg_net"
-- 2. Database → Extensions → habilitar "pg_cron"
-- 3. SQL Editor — configurar variáveis de ambiente do banco:
--      ALTER DATABASE postgres SET "app.supabase_url"     = 'https://SEU_PROJETO.supabase.co';
--      ALTER DATABASE postgres SET "app.service_role_key" = 'sua_service_role_key';
-- 4. Deploy da Edge Function:
--      supabase functions deploy send-push
--      supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"type":"service_account","project_id":...}'
--
-- Depois execute este arquivo inteiro no SQL Editor.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── 0. Novas colunas para rastrear inatividade ────────────────────────────

ALTER TABLE public.motoboys
  ADD COLUMN IF NOT EXISTS last_active_at          TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS inactivity_notif_level  SMALLINT    DEFAULT 0;

-- Índice para as queries de inatividade
CREATE INDEX IF NOT EXISTS idx_motoboys_inactivity
  ON public.motoboys (last_active_at, inactivity_notif_level)
  WHERE is_online = false;


-- ── 1. Helper: envia push para um único token ─────────────────────────────

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
  IF p_token IS NULL OR p_token = '' THEN RETURN; END IF;

  PERFORM net.http_post(
    url     := 'https://lpapiwkfqghdfkekwjnt.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer <SERVICE_ROLE_KEY>'
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


-- ── 2. Trigger: atualiza last_active_at quando motoboy fica online ────────

CREATE OR REPLACE FUNCTION public.fn_motoboy_set_active()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.is_online = true AND (OLD.is_online IS DISTINCT FROM true) THEN
    NEW.last_active_at         := NOW();
    NEW.inactivity_notif_level := 0;   -- reseta para não re-enviar notifs antigas
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_motoboy_set_active ON public.motoboys;
CREATE TRIGGER trg_motoboy_set_active
  BEFORE UPDATE ON public.motoboys
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_motoboy_set_active();


-- ── 3. TRIGGER: nova entrega → notificar todos os motoboys (online ou não) ──

CREATE OR REPLACE FUNCTION public.notify_motoboys_new_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r       RECORD;
  net_val NUMERIC;
BEGIN
  net_val := ROUND((NEW.value - NEW.commission)::NUMERIC, 2);

  FOR r IN
    SELECT u.fcm_token
    FROM   motoboys m
    JOIN   users u ON u.id = m.id
    WHERE  u.fcm_token IS NOT NULL
      AND  m.vehicle_category = NEW.vehicle_category
    LIMIT 50
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


-- ── 4. TRIGGER: mudança de status → notificar cliente e/ou motoboy ───────

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
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  SELECT fcm_token INTO v_client_token
  FROM   users WHERE id = NEW.client_id;

  IF NEW.motoboy_id IS NOT NULL THEN
    SELECT u.fcm_token, u.name
    INTO   v_motoboy_token, v_motoboy_name
    FROM   users u WHERE u.id = NEW.motoboy_id;
  END IF;

  v_net_val := ROUND((NEW.value - NEW.commission)::NUMERIC, 2);

  -- pending → accepted
  IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
    PERFORM public.urbgo_send_push(
      v_client_token,
      'Entregador a caminho!',
      COALESCE(v_motoboy_name, 'Seu entregador') || ' aceitou e está buscando o pacote.',
      jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'accepted')
    );

  -- accepted → in_progress
  ELSIF NEW.status = 'in_progress' AND OLD.status = 'accepted' THEN
    PERFORM public.urbgo_send_push(
      v_client_token,
      'Pacote coletado!',
      'Seu pedido foi retirado e está a caminho do destino.',
      jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'in_progress')
    );

  -- in_progress → completed
  ELSIF NEW.status = 'completed' AND OLD.status = 'in_progress' THEN
    PERFORM public.urbgo_send_push(
      v_client_token,
      'Entrega concluída!',
      'Seu pedido chegou. Avalie seu entregador!',
      jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'completed')
    );
    PERFORM public.urbgo_send_push(
      v_motoboy_token,
      'Corrida finalizada!',
      'Você ganhou R$ ' || v_net_val::TEXT || ' nesta entrega.',
      jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'motoboy', 'type', 'run_completed')
    );

  -- qualquer → cancelled
  ELSIF NEW.status = 'cancelled' THEN
    PERFORM public.urbgo_send_push(
      v_client_token,
      'Entrega cancelada',
      'Sua entrega foi cancelada. Entre em contato com o suporte se precisar.',
      jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'cancelled')
    );
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


-- ── 5. TRIGGER: recarga confirmada → notificar motoboy ───────────────────

CREATE OR REPLACE FUNCTION public.notify_motoboy_recharge()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v_token TEXT; BEGIN
  IF NEW.gateway_status <> 'confirmed' OR OLD.gateway_status = 'confirmed' THEN
    RETURN NEW;
  END IF;

  SELECT u.fcm_token INTO v_token
  FROM   users u WHERE u.id = NEW.motoboy_id;

  PERFORM public.urbgo_send_push(
    v_token,
    'Saldo recarregado!',
    'R$ ' || ROUND(NEW.amount::NUMERIC, 2)::TEXT || ' foram adicionados à sua carteira.',
    jsonb_build_object('role', 'motoboy', 'type', 'recharge', 'amount', NEW.amount::TEXT)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_recharge ON public.recharges;
CREATE TRIGGER trg_notify_recharge
  AFTER UPDATE ON public.recharges
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_motoboy_recharge();


-- ── 6. Notificações de re-engajamento por inatividade ────────────────────
--
-- Lógica de níveis (inactivity_notif_level):
--   0 → nunca notificado (ou voltou a ficar online)
--   1 → notificação de 24 h enviada
--   2 → notificação de 3 dias enviada
--   3 → notificação de 7 dias enviada (encerrado)
--
-- A função avança um nível por vez:
--   nível 0 → 1 quando inactive ≥ 22 h
--   nível 1 → 2 quando inactive ≥ 70 h (≈ 3d)
--   nível 2 → 3 quando inactive ≥ 166 h (≈ 7d)
-- ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_inactive_motoboys()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r         RECORD;
  v_first   TEXT;
  v_hours   NUMERIC;
BEGIN
  FOR r IN
    SELECT
      m.id,
      u.fcm_token,
      u.name,
      m.last_active_at,
      m.inactivity_notif_level,
      EXTRACT(EPOCH FROM (NOW() - m.last_active_at)) / 3600 AS hours_inactive
    FROM motoboys m
    JOIN users u ON u.id = m.id
    WHERE m.is_online = false
      AND u.fcm_token IS NOT NULL
      AND m.last_active_at IS NOT NULL
      AND m.inactivity_notif_level < 3
  LOOP
    v_first := SPLIT_PART(r.name, ' ', 1);
    v_hours := r.hours_inactive;

    -- Nível 0 → 1: inativo por ~24 h
    IF r.inactivity_notif_level = 0 AND v_hours >= 22 THEN
      PERFORM public.urbgo_send_push(
        r.fcm_token,
        'Corridas esperando por você!',
        'Olá ' || v_first || '! Há entregas na sua região. Ligue-se e comece a ganhar!',
        '{"type":"inactivity","level":"1"}'::JSONB
      );
      UPDATE public.motoboys
        SET inactivity_notif_level = 1
        WHERE id = r.id;

    -- Nível 1 → 2: inativo por ~3 dias
    ELSIF r.inactivity_notif_level = 1 AND v_hours >= 70 THEN
      PERFORM public.urbgo_send_push(
        r.fcm_token,
        'Sentimos sua falta, ' || v_first || '!',
        'Faz 3 dias sem entregas. Novas oportunidades de ganho estão esperando por você agora!',
        '{"type":"inactivity","level":"2"}'::JSONB
      );
      UPDATE public.motoboys
        SET inactivity_notif_level = 2
        WHERE id = r.id;

    -- Nível 2 → 3: inativo por ~7 dias
    ELSIF r.inactivity_notif_level = 2 AND v_hours >= 166 THEN
      PERFORM public.urbgo_send_push(
        r.fcm_token,
        'Volte a faturar com UrbGo!',
        'Uma semana sem entregas, ' || v_first || '. Centenas de corridas ficaram sem você. Volte agora!',
        '{"type":"inactivity","level":"3"}'::JSONB
      );
      UPDATE public.motoboys
        SET inactivity_notif_level = 3
        WHERE id = r.id;

    END IF;
  END LOOP;
END;
$$;


-- ── 7. Agendar verificação de inatividade a cada hora (requer pg_cron) ───
--
-- Se pg_cron não estiver habilitado:
--   Dashboard → Database → Extensions → pg_cron → Enable
--
-- Se já existia um schedule anterior, remove antes de criar.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-inactive-motoboys') THEN
    PERFORM cron.unschedule('notify-inactive-motoboys');
  END IF;
END;
$$;

SELECT cron.schedule(
  'notify-inactive-motoboys',
  '0 * * * *',   -- a cada hora
  $$ SELECT public.notify_inactive_motoboys(); $$
);
