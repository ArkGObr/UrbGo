-- ════════════════════════════════════════════════════════════════════════════
-- FIX COMPLETO — Entregas não chegam aos entregadores
-- Execute inteiro no Supabase SQL Editor
--
-- ANTES DE RODAR:
--   Substitua  <<<SUA_SERVICE_ROLE_KEY>>>  na linha indicada no PASSO 2.
--   Você encontra em:  Dashboard → Settings → API → service_role → Reveal
-- ════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- PASSO 1 — Garantir tabela de fila de notificação
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.delivery_notification_targets (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id    UUID        NOT NULL
                   REFERENCES public.deliveries(id) ON DELETE CASCADE,
  motoboy_id     UUID        NOT NULL
                   REFERENCES public.users(id)      ON DELETE CASCADE,
  distance_km    NUMERIC,
  wave           SMALLINT    NOT NULL DEFAULT 0,
  available_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at        TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_dnt_delivery_motoboy UNIQUE (delivery_id, motoboy_id)
);

CREATE INDEX IF NOT EXISTS idx_dnt_motoboy_available
  ON public.delivery_notification_targets (motoboy_id, available_from)
  WHERE sent_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_dnt_delivery_pending
  ON public.delivery_notification_targets (delivery_id)
  WHERE sent_at IS NULL;

-- RLS: motoboy lê apenas as próprias entradas; trigger (SECURITY DEFINER) ignora RLS
ALTER TABLE public.delivery_notification_targets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "dnt_select_own" ON public.delivery_notification_targets;
CREATE POLICY "dnt_select_own"
  ON public.delivery_notification_targets FOR SELECT
  USING (auth.uid() = motoboy_id);

-- Habilitar Realtime para que o app receba atualizações em tempo real
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime
    ADD TABLE public.delivery_notification_targets;
EXCEPTION WHEN others THEN
  NULL; -- tabela já estava na publication
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PASSO 2 — Recriar arkgo_send_push
--
-- ▶ ÚNICA AÇÃO NECESSÁRIA: substitua <<<SUA_SERVICE_ROLE_KEY>>> abaixo
--   pela sua chave real  (Dashboard → Settings → API → service_role → Reveal)
--
-- A chave fica no corpo da função SECURITY DEFINER — só admins do banco
-- conseguem ler definições de funções, então é seguro para uso no Supabase.
-- ═══════════════════════════════════════════════════════════════════════════

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
  v_url TEXT := 'https://lpapiwkfqghdfkekwjnt.supabase.co';
  v_key TEXT := '<<<SUA_SERVICE_ROLE_KEY>>>';  -- ← substitua aqui
BEGIN
  IF p_token IS NULL OR btrim(p_token) = '' THEN RETURN; END IF;

  IF v_key = '<<<SUA_SERVICE_ROLE_KEY>>>' OR btrim(v_key) = '' THEN
    RAISE WARNING '[arkgo_send_push] service_role_key não preenchida na função — push NÃO enviado.';
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
      'data',  COALESCE(p_data, '{}'::JSONB)
    )
  );
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[arkgo_send_push] Erro ao enviar push: %', SQLERRM;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PASSO 3 — Recriar process_delivery_notification_queue
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.process_delivery_notification_queue(
  p_delivery_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r              RECORD;
  v_net          NUMERIC;
  v_net_text     TEXT;
  v_body         TEXT;
BEGIN
  FOR r IN
    SELECT
      t.id,
      t.delivery_id,
      t.distance_km,
      u.fcm_token,
      d.value
    FROM  public.delivery_notification_targets t
    JOIN  public.deliveries d ON d.id = t.delivery_id
    JOIN  public.users u      ON u.id = t.motoboy_id
    WHERE t.sent_at IS NULL
      AND t.available_from <= NOW()
      AND d.status    = 'pending'
      AND d.motoboy_id IS NULL
      AND u.fcm_token IS NOT NULL
      AND (p_delivery_id IS NULL OR t.delivery_id = p_delivery_id)
    ORDER BY t.available_from ASC, t.distance_km ASC
  LOOP
    v_net      := ROUND(r.value::NUMERIC, 2);
    v_net_text := REPLACE(to_char(v_net, 'FM999999990.00'), '.', ',');
    v_body     := 'Você recebe R$ ' || v_net_text
               || ' • a ' || COALESCE(r.distance_km::TEXT, '?') || ' km da coleta';

    PERFORM public.arkgo_send_push(
      r.fcm_token,
      'Nova corrida disponível! 📦',
      v_body,
      jsonb_build_object(
        'deliveryId', r.delivery_id::TEXT,
        'role',       'motoboy',
        'type',       'new_delivery'
      )
    );

    UPDATE public.delivery_notification_targets
       SET sent_at = NOW()
     WHERE id = r.id;
  END LOOP;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PASSO 4 — Recriar notify_motoboys_new_delivery
--           (imediato para todos, sem atraso por onda)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_motoboys_new_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_primary_category   TEXT    := NEW.vehicle_category;
  v_allowed_categories TEXT[];
  v_trip_km            NUMERIC := COALESCE(
    NEW.distance_km,
    public.arkgo_distance_km(
      NEW.pickup_lat, NEW.pickup_lng,
      NEW.delivery_lat, NEW.delivery_lng
    )
  );
  v_has_primary_online BOOLEAN;
BEGIN
  -- Verifica se existe algum motoboy da categoria primária online próximo
  SELECT EXISTS (
    SELECT 1
    FROM  public.motoboys m
    JOIN  public.users u ON u.id = m.id
    CROSS JOIN LATERAL (
      SELECT public.arkgo_distance_km(
        m.current_lat, m.current_lng,
        NEW.pickup_lat, NEW.pickup_lng
      ) AS d
    ) dist
    WHERE m.is_online = TRUE
      AND m.vehicle_category = v_primary_category
      AND m.current_lat IS NOT NULL
      AND m.current_lng IS NOT NULL
      AND dist.d IS NOT NULL
      AND dist.d <= 15
  ) INTO v_has_primary_online;

  v_allowed_categories := ARRAY[v_primary_category];

  -- Fallback de categoria quando não há ninguém da categoria primária próximo
  IF NOT v_has_primary_online THEN
    IF v_primary_category = 'bike' THEN
      -- Bike sem bike online → aceita motoboy também
      v_allowed_categories := ARRAY['bike', 'motoboy'];
    ELSIF v_primary_category = 'motoboy'
      AND COALESCE(v_trip_km, 999999) <= 3 THEN
      -- Motoboy curto sem motoboy online → aceita bike também
      v_allowed_categories := ARRAY['motoboy', 'bike'];
    END IF;
  END IF;

  -- Insere todos os elegíveis disponíveis IMEDIATAMENTE (available_from = NOW())
  INSERT INTO public.delivery_notification_targets (
    delivery_id, motoboy_id, distance_km, wave, available_from
  )
  SELECT
    NEW.id,
    m.id,
    dist.d,
    CASE
      WHEN dist.d <= 3  THEN 0
      WHEN dist.d <= 7  THEN 1
      WHEN dist.d <= 11 THEN 2
      ELSE 3
    END,
    NOW()
  FROM  public.motoboys m
  JOIN  public.users u ON u.id = m.id
  CROSS JOIN LATERAL (
    SELECT public.arkgo_distance_km(
      m.current_lat, m.current_lng,
      NEW.pickup_lat, NEW.pickup_lng
    ) AS d
  ) dist
  WHERE m.is_online = TRUE
    AND m.vehicle_category = ANY(v_allowed_categories)
    AND m.current_lat IS NOT NULL
    AND m.current_lng IS NOT NULL
    AND dist.d IS NOT NULL
    AND dist.d <= 15
  ORDER BY
    CASE WHEN m.vehicle_category = v_primary_category THEN 0 ELSE 1 END ASC,
    dist.d ASC
  LIMIT 100
  ON CONFLICT (delivery_id, motoboy_id) DO NOTHING;

  -- Envia os pushes imediatamente para todos na fila
  PERFORM public.process_delivery_notification_queue(NEW.id);
  RETURN NEW;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PASSO 5 — Recriar notify_delivery_status_change
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_delivery_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_client_token  TEXT;
  v_motoboy_token TEXT;
  v_motoboy_name  TEXT;
  v_net_text      TEXT;
BEGIN
  BEGIN
    IF OLD.status = NEW.status THEN RETURN NEW; END IF;

    SELECT fcm_token INTO v_client_token
    FROM   public.users WHERE id = NEW.client_id;

    IF NEW.motoboy_id IS NOT NULL THEN
      SELECT u.fcm_token, u.name
      INTO   v_motoboy_token, v_motoboy_name
      FROM   public.users u WHERE u.id = NEW.motoboy_id;
    END IF;

    v_net_text := REPLACE(
      to_char(ROUND(NEW.value::NUMERIC, 2), 'FM999999990.00'),
      '.', ','
    );

    -- pending → accepted
    IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
      PERFORM public.arkgo_send_push(
        v_client_token,
        'Entregador a caminho! 🏍️',
        COALESCE(v_motoboy_name, 'Seu entregador') || ' aceitou e está buscando o pacote.',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'accepted')
      );

    -- accepted → in_progress
    ELSIF NEW.status = 'in_progress' AND OLD.status = 'accepted' THEN
      PERFORM public.arkgo_send_push(
        v_client_token,
        'Pacote coletado! 📦',
        'Seu pedido foi retirado e está a caminho do destino.',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'in_progress')
      );

    -- in_progress → completed
    ELSIF NEW.status = 'completed' AND OLD.status = 'in_progress' THEN
      PERFORM public.arkgo_send_push(
        v_client_token,
        'Entrega concluída! ✓',
        'Seu pedido chegou com sucesso. Avalie seu entregador!',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'completed')
      );
      PERFORM public.arkgo_send_push(
        v_motoboy_token,
        'Corrida finalizada! 💰',
        'Você ganhou R$ ' || v_net_text || ' nesta entrega.',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'motoboy', 'type', 'run_completed')
      );

    -- qualquer → cancelled
    ELSIF NEW.status = 'cancelled' THEN
      PERFORM public.arkgo_send_push(
        v_client_token,
        'Entrega cancelada',
        'Sua entrega foi cancelada. Fale com o suporte se precisar.',
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
    RAISE WARNING '[notify_delivery_status_change] Erro: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- PASSO 6 — Recriar os triggers
-- ═══════════════════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS trg_notify_new_delivery    ON public.deliveries;
DROP TRIGGER IF EXISTS trg_notify_delivery_status ON public.deliveries;

CREATE TRIGGER trg_notify_new_delivery
  AFTER INSERT ON public.deliveries
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_motoboys_new_delivery();

CREATE TRIGGER trg_notify_delivery_status
  AFTER UPDATE ON public.deliveries
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_delivery_status_change();


-- ═══════════════════════════════════════════════════════════════════════════
-- PASSO 7 — Reprocessar entregas pendentes criadas enquanto os triggers
--           estavam quebrados (backfill das últimas 24 horas)
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  r             RECORD;
  v_count       INT := 0;
  v_inserted    INT;
BEGIN
  FOR r IN
    SELECT d.*
    FROM   public.deliveries d
    WHERE  d.status = 'pending'
      AND  d.motoboy_id IS NULL
      AND  d.created_at >= NOW() - INTERVAL '24 hours'
      AND  NOT EXISTS (
             SELECT 1
             FROM   public.delivery_notification_targets t
             WHERE  t.delivery_id = d.id
           )
  LOOP
    WITH ins AS (
      INSERT INTO public.delivery_notification_targets (
        delivery_id, motoboy_id, distance_km, wave, available_from
      )
      SELECT
        r.id,
        m.id,
        dist.d,
        0,
        NOW()
      FROM  public.motoboys m
      JOIN  public.users u ON u.id = m.id
      CROSS JOIN LATERAL (
        SELECT public.arkgo_distance_km(
          m.current_lat, m.current_lng,
          r.pickup_lat, r.pickup_lng
        ) AS d
      ) dist
      WHERE m.is_online = TRUE
        AND m.vehicle_category = r.vehicle_category
        AND m.current_lat IS NOT NULL
        AND m.current_lng IS NOT NULL
        AND dist.d IS NOT NULL
        AND dist.d <= 15
      ON CONFLICT (delivery_id, motoboy_id) DO NOTHING
      RETURNING 1
    )
    SELECT COUNT(*) INTO v_inserted FROM ins;

    v_count := v_count + 1;
    RAISE NOTICE 'Entrega % → % motoboys na fila.', r.id, v_inserted;
  END LOOP;

  RAISE NOTICE '=== Backfill concluído: % entrega(s) reprocessada(s). ===', v_count;
END;
$$;

-- Envia os pushes para tudo que está na fila e ainda não foi enviado
SELECT public.process_delivery_notification_queue();


-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICAÇÃO FINAL — Execute ao término para confirmar o estado
-- ═══════════════════════════════════════════════════════════════════════════

SELECT
  '1. Triggers ativos' AS check,
  string_agg(tgname, ', ' ORDER BY tgname) AS resultado
FROM pg_trigger
WHERE tgrelid = 'public.deliveries'::regclass
  AND tgenabled = 'O'

UNION ALL

SELECT
  '2. Função arkgo_send_push',
  CASE
    WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'arkgo_send_push' AND pronamespace = 'public'::regnamespace)
    THEN 'OK — função existe (verifique se a key foi preenchida)'
    ELSE 'PROBLEMA — função não encontrada!'
  END

UNION ALL

SELECT
  '3. Entregas pendentes sem motoboy',
  COUNT(*)::TEXT
FROM public.deliveries
WHERE status = 'pending' AND motoboy_id IS NULL

UNION ALL

SELECT
  '4. Registros na fila (não enviados)',
  COUNT(*)::TEXT
FROM public.delivery_notification_targets
WHERE sent_at IS NULL

UNION ALL

SELECT
  '5. Motoboys online agora',
  COUNT(*)::TEXT
FROM public.motoboys
WHERE is_online = TRUE

UNION ALL

SELECT
  '6. Motoboys online com GPS',
  COUNT(*)::TEXT
FROM public.motoboys
WHERE is_online = TRUE
  AND current_lat IS NOT NULL
  AND current_lng IS NOT NULL;
