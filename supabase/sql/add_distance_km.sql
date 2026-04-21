-- Adiciona a coluna distance_km na tabela deliveries
-- Esta coluna armazena a distância real calculada pelo OSRM no momento de criação da entrega,
-- garantindo que todos os displays (cliente, motoboy, admin) usem o mesmo valor que gerou o preço.

ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS distance_km NUMERIC(8,2);

-- Índice opcional para queries de análise por faixa de distância
CREATE INDEX IF NOT EXISTS idx_deliveries_distance_km ON public.deliveries (distance_km);
