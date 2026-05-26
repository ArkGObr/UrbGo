CREATE TABLE IF NOT EXISTS public.pricing_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  rule_type TEXT NOT NULL CHECK (rule_type IN ('weekly', 'specific_date')),
  days TEXT NOT NULL,
  start_hour INTEGER NOT NULL CHECK (start_hour >= 0 AND start_hour <= 24),
  end_hour INTEGER NOT NULL CHECK (end_hour >= 0 AND end_hour <= 24),
  multipliers JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT true
);

ALTER TABLE public.pricing_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pricing_rules: leitura pública" ON public.pricing_rules;
CREATE POLICY "pricing_rules: leitura pública"
  ON public.pricing_rules FOR SELECT USING (true);
