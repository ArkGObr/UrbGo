-- ═══════════════════════════════════════════════════════════════
-- Sistema de avaliações de entregadores
-- ═══════════════════════════════════════════════════════════════

-- Colunas de rating no motoboy
ALTER TABLE motoboys
  ADD COLUMN IF NOT EXISTS avg_rating    NUMERIC(3,2) NOT NULL DEFAULT 5.00,
  ADD COLUMN IF NOT EXISTS total_ratings INTEGER      NOT NULL DEFAULT 0;

-- Tabela de avaliações (1 por entrega concluída)
CREATE TABLE IF NOT EXISTS public.delivery_ratings (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id UUID NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
  client_id   UUID NOT NULL REFERENCES users(id)      ON DELETE CASCADE,
  motoboy_id  UUID NOT NULL REFERENCES motoboys(id)   ON DELETE CASCADE,
  rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT delivery_ratings_delivery_id_unique UNIQUE (delivery_id)
);

-- RLS
ALTER TABLE public.delivery_ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Client can insert own ratings"         ON public.delivery_ratings;
DROP POLICY IF EXISTS "Client can read own ratings"           ON public.delivery_ratings;
DROP POLICY IF EXISTS "Motoboy can read ratings about themselves" ON public.delivery_ratings;

CREATE POLICY "Client can insert own ratings"
  ON public.delivery_ratings FOR INSERT
  WITH CHECK (auth.uid() = client_id);

CREATE POLICY "Client can read own ratings"
  ON public.delivery_ratings FOR SELECT
  USING (auth.uid() = client_id);

CREATE POLICY "Motoboy can read ratings about themselves"
  ON public.delivery_ratings FOR SELECT
  USING (auth.uid() = motoboy_id);

-- Trigger: recalcula avg_rating + total_ratings ao inserir avaliação
CREATE OR REPLACE FUNCTION public.update_motoboy_rating()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE motoboys
  SET
    avg_rating    = (SELECT ROUND(AVG(rating)::NUMERIC, 2) FROM delivery_ratings WHERE motoboy_id = NEW.motoboy_id),
    total_ratings = (SELECT COUNT(*)                       FROM delivery_ratings WHERE motoboy_id = NEW.motoboy_id)
  WHERE id = NEW.motoboy_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_delivery_rating_insert ON public.delivery_ratings;
CREATE TRIGGER on_delivery_rating_insert
  AFTER INSERT ON public.delivery_ratings
  FOR EACH ROW EXECUTE FUNCTION public.update_motoboy_rating();
