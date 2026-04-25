-- ================================================================
-- UrbGO — Migration: Novos campos por categoria de entrega
-- Versão: 2026-04-24
-- Executar no Supabase SQL Editor (Dashboard > SQL Editor)
-- ================================================================

-- Adiciona todos os novos campos na tabela deliveries
ALTER TABLE deliveries
  ADD COLUMN IF NOT EXISTS recipient_name    text,
  ADD COLUMN IF NOT EXISTS recipient_phone   text,
  ADD COLUMN IF NOT EXISTS item_description  text,
  ADD COLUMN IF NOT EXISTS is_fragile        boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS declared_value    numeric(10,2),
  ADD COLUMN IF NOT EXISTS helper_count      smallint DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_round_trip     boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS scheduled_for     timestamptz,
  ADD COLUMN IF NOT EXISTS cargo_type        text;

-- Comentários descritivos dos campos
COMMENT ON COLUMN deliveries.recipient_name    IS 'Nome do destinatário (obrigatório no novo fluxo)';
COMMENT ON COLUMN deliveries.recipient_phone   IS 'Telefone do destinatário (obrigatório no novo fluxo)';
COMMENT ON COLUMN deliveries.item_description  IS 'Observações/instruções para o entregador';
COMMENT ON COLUMN deliveries.is_fragile        IS 'Flag: item frágil / manuseie com cuidado';
COMMENT ON COLUMN deliveries.declared_value    IS 'Valor declarado pelo cliente para fins de seguro';
COMMENT ON COLUMN deliveries.helper_count      IS 'Número de ajudantes solicitados (0, 1, 2, 3) — Van e Carreto';
COMMENT ON COLUMN deliveries.is_round_trip     IS 'Opção de ida e volta (motorista retorna ao ponto de coleta)';
COMMENT ON COLUMN deliveries.scheduled_for     IS 'Data/hora agendada. NULL = coleta imediata';
COMMENT ON COLUMN deliveries.cargo_type        IS 'Tipo de carga: furniture | appliances | construction | other';

-- ================================================================
-- Verificar resultado
-- ================================================================
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'deliveries'
  AND column_name IN (
    'recipient_name', 'recipient_phone', 'item_description',
    'is_fragile', 'declared_value', 'helper_count',
    'is_round_trip', 'scheduled_for', 'cargo_type'
  )
ORDER BY column_name;
