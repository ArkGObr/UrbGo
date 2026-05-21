-- Adiciona coluna rg_number para entregadores de bike (que não possuem CNH)
ALTER TABLE motoboys
  ADD COLUMN IF NOT EXISTS rg_number text;
