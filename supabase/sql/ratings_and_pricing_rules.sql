-- ═══════════════════════════════════════════════════════════════
-- RATINGS — Sistema de avaliações de entregadores
-- ═══════════════════════════════════════════════════════════════

-- Colunas de rating no motoboy
ALTER TABLE motoboys
  ADD COLUMN IF NOT EXISTS avg_rating  NUMERIC(3,2) NOT NULL DEFAULT 5.00,
  ADD COLUMN IF NOT EXISTS total_ratings INTEGER      NOT NULL DEFAULT 0;

-- Tabela de avaliações (1 por entrega concluída)
CREATE TABLE IF NOT EXISTS public.delivery_ratings (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id UUID NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
  client_id   UUID NOT NULL REFERENCES users(id)     ON DELETE CASCADE,
  motoboy_id  UUID NOT NULL REFERENCES motoboys(id)  ON DELETE CASCADE,
  rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT delivery_ratings_delivery_id_unique UNIQUE (delivery_id)
);

-- RLS
ALTER TABLE public.delivery_ratings ENABLE ROW LEVEL SECURITY;

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

-- ═══════════════════════════════════════════════════════════════
-- PEAK HOURS — Regras de precificação dinâmica
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.peak_hours_rules (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT    NOT NULL,
  description  TEXT,
  multiplier   NUMERIC(4,2) NOT NULL DEFAULT 1.00,
  start_hour   SMALLINT NOT NULL CHECK (start_hour BETWEEN 0 AND 23),
  end_hour     SMALLINT NOT NULL CHECK (end_hour   BETWEEN 0 AND 23),
  -- 0=dom, 1=seg, 2=ter, 3=qua, 4=qui, 5=sex, 6=sab
  days_of_week INTEGER[] NOT NULL DEFAULT ARRAY[0,1,2,3,4,5,6],
  is_active    BOOLEAN  NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS: apenas leitura pública (sem autenticação necessária para consultar)
ALTER TABLE public.peak_hours_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read active rules"
  ON public.peak_hours_rules FOR SELECT
  USING (is_active = true);

-- Regras padrão baseadas no mercado de delivery brasileiro:
-- Almoço (seg-sex 11h-14h): +30% — pico de pedidos de comida/documentos
-- Noite (todos os dias 17h-21h): +40% — maior demanda do dia, trânsito pesado
-- Madrugada (todos 0h-5h): -10% — baixíssima demanda, incentivo ao motoboy
-- Final de semana dia (sab-dom 9h-22h): +20% — movimento elevado de lazer/comércio
INSERT INTO public.peak_hours_rules (name, description, multiplier, start_hour, end_hour, days_of_week)
VALUES
  ('Horário de Almoço',    'Pico de entregas de segunda a sexta, horário de almoço',     1.30, 11, 14, ARRAY[1,2,3,4,5]),
  ('Horário de Pico Noturno', 'Maior demanda diária, inclui saída do trabalho e jantar', 1.40, 17, 21, ARRAY[0,1,2,3,4,5,6]),
  ('Madrugada',            'Baixa demanda — desconto para estimular pedidos',             0.90,  0,  5, ARRAY[0,1,2,3,4,5,6]),
  ('Final de Semana',      'Fim de semana com movimento elevado de lazer e comércio',    1.20,  9, 22, ARRAY[0,6])
ON CONFLICT DO NOTHING;
