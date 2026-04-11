-- ═══════════════════════════════════════════════════════════════
-- URBGO — Atualização de Colunas do Cadastro do Motoboy
-- Execute este bloco completo no Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Adiciona as colunas do cadastro do motoboy caso não existam
ALTER TABLE public.motoboys
  ADD COLUMN IF NOT EXISTS vehicle_plate TEXT,
  ADD COLUMN IF NOT EXISTS vehicle_category TEXT,
  ADD COLUMN IF NOT EXISTS vehicle_model TEXT,
  ADD COLUMN IF NOT EXISTS vehicle_year INTEGER;
