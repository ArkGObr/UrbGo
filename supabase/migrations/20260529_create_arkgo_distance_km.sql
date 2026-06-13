-- ============================================================
-- Cria (ou recria) a função arkgo_distance_km
-- Calcula distância Haversine entre dois pontos (lat/lng)
-- Retorna resultado em quilômetros com 2 casas decimais
-- ============================================================

CREATE OR REPLACE FUNCTION public.arkgo_distance_km(
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
