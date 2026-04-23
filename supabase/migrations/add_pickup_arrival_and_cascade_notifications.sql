-- ============================================================
-- Media prioridade / notificacoes:
--   M3. Aviso real quando entregador chegar ao ponto de coleta
--   Nova corrida em cascata por proximidade ate 15 km
-- ============================================================

ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS pickup_arrival_notified_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.delivery_notification_targets (
  id             BIGSERIAL PRIMARY KEY,
  delivery_id    UUID        NOT NULL REFERENCES public.deliveries(id) ON DELETE CASCADE,
  motoboy_id     UUID        NOT NULL REFERENCES public.motoboys(id)   ON DELETE CASCADE,
  distance_km    NUMERIC(8,2) NOT NULL,
  wave           INTEGER      NOT NULL,
  available_from TIMESTAMPTZ  NOT NULL,
  sent_at        TIMESTAMPTZ,
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CONSTRAINT delivery_notification_targets_unique UNIQUE (delivery_id, motoboy_id)
);

CREATE INDEX IF NOT EXISTS delivery_notification_targets_pending_idx
  ON public.delivery_notification_targets(delivery_id, sent_at, available_from);

CREATE OR REPLACE FUNCTION public.urbgo_distance_km(
  lat1 DOUBLE PRECISION,
  lng1 DOUBLE PRECISION,
  lat2 DOUBLE PRECISION,
  lng2 DOUBLE PRECISION
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  dlat DOUBLE PRECISION;
  dlng DOUBLE PRECISION;
  a    DOUBLE PRECISION;
  c    DOUBLE PRECISION;
  r    DOUBLE PRECISION := 6371.0;
BEGIN
  IF lat1 IS NULL OR lng1 IS NULL OR lat2 IS NULL OR lng2 IS NULL THEN
    RETURN NULL;
  END IF;

  dlat := radians(lat2 - lat1);
  dlng := radians(lng2 - lng1);
  a := sin(dlat / 2) * sin(dlat / 2)
    + cos(radians(lat1)) * cos(radians(lat2))
    * sin(dlng / 2) * sin(dlng / 2);
  c := 2 * atan2(sqrt(a), sqrt(1 - a));

  RETURN ROUND((r * c)::NUMERIC, 2);
END;
$$;

CREATE OR REPLACE FUNCTION public.process_delivery_notification_queue(
  p_delivery_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r         RECORD;
  v_net_val NUMERIC;
  v_body    TEXT;
BEGIN
  FOR r IN
    SELECT
      t.id,
      t.delivery_id,
      t.distance_km,
      u.fcm_token,
      d.value,
      d.commission
    FROM public.delivery_notification_targets t
    JOIN public.deliveries d ON d.id = t.delivery_id
    JOIN public.users u      ON u.id = t.motoboy_id
    WHERE t.sent_at IS NULL
      AND t.available_from <= NOW()
      AND d.status = 'pending'
      AND d.motoboy_id IS NULL
      AND u.fcm_token IS NOT NULL
      AND (p_delivery_id IS NULL OR t.delivery_id = p_delivery_id)
    ORDER BY t.available_from ASC, t.distance_km ASC
  LOOP
    v_net_val := ROUND((r.value - r.commission)::NUMERIC, 2);
    v_body := 'Voce recebe R$ ' || v_net_val::TEXT
      || ' • a ' || r.distance_km::TEXT || ' km da coleta';

    PERFORM public.urbgo_send_push(
      r.fcm_token,
      'Nova corrida disponivel! 📦',
      v_body,
      jsonb_build_object(
        'deliveryId', r.delivery_id::TEXT,
        'role', 'motoboy',
        'type', 'new_delivery'
      )
    );

    UPDATE public.delivery_notification_targets
    SET sent_at = NOW()
    WHERE id = r.id;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_motoboys_new_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.delivery_notification_targets (
    delivery_id,
    motoboy_id,
    distance_km,
    wave,
    available_from
  )
  SELECT
    NEW.id,
    m.id,
    dist.distance_km,
    CASE
      WHEN dist.distance_km <= 3 THEN 0
      WHEN dist.distance_km <= 7 THEN 1
      WHEN dist.distance_km <= 11 THEN 2
      ELSE 3
    END AS wave,
    NOW() +
      CASE
        WHEN dist.distance_km <= 3 THEN INTERVAL '0 minute'
        WHEN dist.distance_km <= 7 THEN INTERVAL '2 minutes'
        WHEN dist.distance_km <= 11 THEN INTERVAL '4 minutes'
        ELSE INTERVAL '6 minutes'
      END AS available_from
  FROM public.motoboys m
  JOIN public.users u ON u.id = m.id
  CROSS JOIN LATERAL (
    SELECT public.urbgo_distance_km(
      m.current_lat,
      m.current_lng,
      NEW.pickup_lat,
      NEW.pickup_lng
    ) AS distance_km
  ) dist
  WHERE m.is_online = TRUE
    AND u.fcm_token IS NOT NULL
    AND m.vehicle_category = NEW.vehicle_category
    AND m.current_lat IS NOT NULL
    AND m.current_lng IS NOT NULL
    AND dist.distance_km IS NOT NULL
    AND dist.distance_km <= 15
  ORDER BY dist.distance_km ASC
  LIMIT 100
  ON CONFLICT (delivery_id, motoboy_id) DO NOTHING;

  PERFORM public.process_delivery_notification_queue(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_new_delivery ON public.deliveries;
CREATE TRIGGER trg_notify_new_delivery
  AFTER INSERT ON public.deliveries
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_motoboys_new_delivery();

CREATE OR REPLACE FUNCTION public.notify_client_pickup_arrival()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r RECORD;
BEGIN
  IF NEW.current_lat IS NULL OR NEW.current_lng IS NULL THEN
    RETURN NEW;
  END IF;

  FOR r IN
    SELECT
      d.id AS delivery_id,
      u.fcm_token
    FROM public.deliveries d
    JOIN public.users u ON u.id = d.client_id
    WHERE d.motoboy_id = NEW.id
      AND d.status = 'accepted'
      AND d.pickup_arrival_notified_at IS NULL
      AND u.fcm_token IS NOT NULL
      AND public.urbgo_distance_km(
            NEW.current_lat,
            NEW.current_lng,
            d.pickup_lat,
            d.pickup_lng
          ) <= 0.15
  LOOP
    PERFORM public.urbgo_send_push(
      r.fcm_token,
      'Entregador chegou à coleta',
      'Seu pedido está prestes a ser retirado.',
      jsonb_build_object(
        'deliveryId', r.delivery_id::TEXT,
        'role', 'client',
        'type', 'pickup_arrival'
      )
    );

    UPDATE public.deliveries
    SET pickup_arrival_notified_at = NOW()
    WHERE id = r.delivery_id
      AND pickup_arrival_notified_at IS NULL;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_pickup_arrival ON public.motoboys;
CREATE TRIGGER trg_notify_pickup_arrival
  AFTER UPDATE OF current_lat, current_lng ON public.motoboys
  FOR EACH ROW
  WHEN (
    OLD.current_lat IS DISTINCT FROM NEW.current_lat
    OR OLD.current_lng IS DISTINCT FROM NEW.current_lng
  )
  EXECUTE FUNCTION public.notify_client_pickup_arrival();

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'process-delivery-notification-cascade'
  ) THEN
    PERFORM cron.unschedule('process-delivery-notification-cascade');
  END IF;
END $$;

SELECT cron.schedule(
  'process-delivery-notification-cascade',
  '* * * * *',
  'SELECT public.process_delivery_notification_queue()'
);
