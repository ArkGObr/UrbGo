-- ============================================================
-- Ajusta despacho por categoria:
-- - bike sem bike online -> permite motoboy
-- - motoboy ate 3 km sem motoboy online -> permite bike
-- ============================================================

CREATE OR REPLACE FUNCTION public.notify_motoboys_new_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_primary_category  TEXT := NEW.vehicle_category;
  v_allowed_categories TEXT[];
  v_trip_distance_km  NUMERIC := COALESCE(
    NEW.distance_km,
    public.arkgo_distance_km(
      NEW.pickup_lat,
      NEW.pickup_lng,
      NEW.delivery_lat,
      NEW.delivery_lng
    )
  );
  v_has_primary_online BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.motoboys m
    JOIN public.users u ON u.id = m.id
    CROSS JOIN LATERAL (
      SELECT public.arkgo_distance_km(
        m.current_lat,
        m.current_lng,
        NEW.pickup_lat,
        NEW.pickup_lng
      ) AS distance_km
    ) dist
    WHERE m.is_online = TRUE
      AND u.fcm_token IS NOT NULL
      AND m.vehicle_category = v_primary_category
      AND m.current_lat IS NOT NULL
      AND m.current_lng IS NOT NULL
      AND dist.distance_km IS NOT NULL
      AND dist.distance_km <= 15
  ) INTO v_has_primary_online;

  v_allowed_categories := ARRAY[v_primary_category];

  IF NOT v_has_primary_online THEN
    IF v_primary_category = 'bike' THEN
      v_allowed_categories := ARRAY['bike', 'motoboy'];
    ELSIF v_primary_category = 'motoboy'
      AND COALESCE(v_trip_distance_km, 999999) <= 3 THEN
      v_allowed_categories := ARRAY['motoboy', 'bike'];
    END IF;
  END IF;

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
    SELECT public.arkgo_distance_km(
      m.current_lat,
      m.current_lng,
      NEW.pickup_lat,
      NEW.pickup_lng
    ) AS distance_km
  ) dist
  WHERE m.is_online = TRUE
    AND u.fcm_token IS NOT NULL
    AND m.vehicle_category = ANY(v_allowed_categories)
    AND m.current_lat IS NOT NULL
    AND m.current_lng IS NOT NULL
    AND dist.distance_km IS NOT NULL
    AND dist.distance_km <= 15
  ORDER BY
    CASE
      WHEN m.vehicle_category = v_primary_category THEN 0
      ELSE 1
    END ASC,
    dist.distance_km ASC
  LIMIT 100
  ON CONFLICT (delivery_id, motoboy_id) DO NOTHING;

  PERFORM public.process_delivery_notification_queue(NEW.id);
  RETURN NEW;
END;
$$;
