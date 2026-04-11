-- ══════════════════════════════════════════════════════════════
-- PIVOT: Categorias de Veículos
-- Execute APÓS o SQL da FASE_00
-- ══════════════════════════════════════════════════════════════

-- 1. Adicionar colunas de categoria/veículo ao perfil do entregador
ALTER TABLE public.motoboys
  ADD COLUMN IF NOT EXISTS vehicle_category TEXT
    NOT NULL DEFAULT 'motoboy'
    CHECK (vehicle_category IN ('bike','motoboy','mototaxi','car','van','caminhao'));

ALTER TABLE public.motoboys
  ADD COLUMN IF NOT EXISTS vehicle_model TEXT;

ALTER TABLE public.motoboys
  ADD COLUMN IF NOT EXISTS vehicle_year  SMALLINT;

-- 2. Adicionar categoria solicitada na entrega
ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS vehicle_category TEXT
    NOT NULL DEFAULT 'motoboy'
    CHECK (vehicle_category IN ('bike','motoboy','mototaxi','car','van','caminhao'));

-- 3. Índices para filtrar por categoria (performance)
CREATE INDEX IF NOT EXISTS idx_deliveries_category
  ON public.deliveries(vehicle_category, status);

CREATE INDEX IF NOT EXISTS idx_motoboys_category
  ON public.motoboys(vehicle_category, is_online);

-- 4. Atualizar policy: motoboy vê apenas corridas da sua categoria
DROP POLICY IF EXISTS "deliveries: motoboy vê pendentes" ON public.deliveries;

CREATE POLICY "deliveries: motoboy vê pendentes por categoria"
  ON public.deliveries FOR SELECT
  USING (
    status = 'pending'
    AND EXISTS (
      SELECT 1 FROM public.motoboys
      WHERE id = auth.uid()
        AND vehicle_category = deliveries.vehicle_category
    )
  );

-- 5. Tabela de preços (referência — cálculo feito no app)
CREATE TABLE IF NOT EXISTS public.vehicle_pricing (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category        TEXT UNIQUE NOT NULL,
  name            TEXT NOT NULL,
  base_rate       NUMERIC(8,2) NOT NULL,
  per_km_rate     NUMERIC(8,2) NOT NULL,
  min_fare        NUMERIC(8,2) NOT NULL,
  commission_rate NUMERIC(4,3) NOT NULL DEFAULT 0.250,
  is_active       BOOLEAN NOT NULL DEFAULT true,
  updated_at      TIMESTAMPTZ DEFAULT now()
);

INSERT INTO public.vehicle_pricing
  (category, name, base_rate, per_km_rate, min_fare) VALUES
  ('bike',     'Bike',       4.00,  1.20,  6.00),
  ('motoboy',  'Motoboy',    5.00,  1.50,  8.00),
  ('mototaxi', 'Mototáxi',   6.00,  1.80, 10.00),
  ('car',      'Carro',      10.00, 2.50, 18.00),
  ('van',      'Utilitário', 20.00, 3.50, 35.00),
  ('caminhao', 'Caminhão',   50.00, 6.00, 90.00)
ON CONFLICT (category) DO NOTHING;

-- RLS para vehicle_pricing (leitura pública)
ALTER TABLE public.vehicle_pricing ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pricing: leitura pública" ON public.vehicle_pricing;
CREATE POLICY "pricing: leitura pública"
  ON public.vehicle_pricing FOR SELECT USING (true);
