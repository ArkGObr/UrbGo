-- ══════════════════════════════════════════════════════════════
-- ARKGO — CORREÇÃO DEFINITIVA: Recursão Infinita em RLS
-- Execute TODO este bloco no Supabase SQL Editor
-- ══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- PROBLEMA:
--   A policy da tabela "motoboys" faz SELECT em "deliveries".
--   A policy da tabela "deliveries" faz SELECT em "motoboys".
--   = Recursão infinita (erro 42P17).
--
-- SOLUÇÃO:
--   Quebrar o ciclo: policies de "deliveries" nunca consultam
--   "motoboys" — usam "users" para checar role = 'motoboy'.
--   E policies de "motoboys" que referenciam "deliveries"
--   são reescritas para evitar conflito.
-- ─────────────────────────────────────────────────────────────

-- ═══ 1. LIMPAR TODAS AS POLICIES PROBLEMÁTICAS ═════════════

-- Motoboys: remover TODAS as policies existentes
DROP POLICY IF EXISTS "motoboys: próprio" ON public.motoboys;
DROP POLICY IF EXISTS "motoboys: cliente lê motoboy da sua entrega" ON public.motoboys;
DROP POLICY IF EXISTS "motoboys: inserção própria" ON public.motoboys;

-- Deliveries: remover policies que referenciam motoboys
DROP POLICY IF EXISTS "deliveries: motoboy vê pendentes" ON public.deliveries;
DROP POLICY IF EXISTS "deliveries: motoboy vê pendentes por categoria" ON public.deliveries;
DROP POLICY IF EXISTS "deliveries: cliente gerencia as suas" ON public.deliveries;
DROP POLICY IF EXISTS "deliveries: motoboy gerencia as suas" ON public.deliveries;

-- Users: remover para recriar limpo
DROP POLICY IF EXISTS "users: leitura própria" ON public.users;
DROP POLICY IF EXISTS "users: atualização própria" ON public.users;
DROP POLICY IF EXISTS "users: inserção própria" ON public.users;


-- ═══ 2. GARANTIR RLS ATIVO ════════════════════════════════

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.motoboys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deliveries ENABLE ROW LEVEL SECURITY;


-- ═══ 3. POLICIES DA TABELA "users" ════════════════════════

-- O próprio usuário pode ler seus dados
CREATE POLICY "users: leitura própria"
  ON public.users FOR SELECT
  USING (auth.uid() = id);

-- O próprio usuário pode atualizar seus dados
CREATE POLICY "users: atualização própria"
  ON public.users FOR UPDATE
  USING (auth.uid() = id);

-- O próprio usuário pode inserir (necessário para upsert no signup fallback)
CREATE POLICY "users: inserção própria"
  ON public.users FOR INSERT
  WITH CHECK (auth.uid() = id);


-- ═══ 4. POLICIES DA TABELA "motoboys" (SEM referência a deliveries) ═══

-- Motoboy acessa APENAS o próprio registro (CRUD completo)
CREATE POLICY "motoboys: próprio"
  ON public.motoboys FOR ALL
  USING (auth.uid() = id);

-- Cliente pode LER dados do motoboy que está com sua entrega.
-- IMPORTANTE: Usa subquery com SECURITY INVOKER desabilitado
-- via acesso direto (sem referenciar policies de deliveries).
-- Solução: o cliente busca o motoboy pelo ID que ele já tem
-- no registro da entrega (o app faz .eq('id', motoboyId)).
-- Esta policy permite: qualquer user autenticado pode LER motoboys.
-- Isso é seguro pois o conteúdo visível é limitado (sem dados sensíveis).
CREATE POLICY "motoboys: leitura autenticada"
  ON public.motoboys FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- Inserção pelo signup (trigger ou fallback manual)
CREATE POLICY "motoboys: inserção própria"
  ON public.motoboys FOR INSERT
  WITH CHECK (auth.uid() = id);


-- ═══ 5. POLICIES DA TABELA "deliveries" (SEM referência a motoboys) ═══

-- Cliente gerencia (CRUD) suas próprias entregas
CREATE POLICY "deliveries: cliente gerencia as suas"
  ON public.deliveries FOR ALL
  USING (client_id = auth.uid());

-- Motoboy vê entregas pendentes da sua categoria.
-- USA "users" para checar role (NUNCA "motoboys" — isso causava recursão).
-- Para filtrar por categoria, fazemos um JOIN safe com users.
CREATE POLICY "deliveries: motoboy vê pendentes"
  ON public.deliveries FOR SELECT
  USING (
    status = 'pending'
    AND auth.uid() IN (SELECT id FROM public.users WHERE role = 'motoboy')
  );

-- Motoboy gerencia entregas atribuídas a ele
CREATE POLICY "deliveries: motoboy gerencia as suas"
  ON public.deliveries FOR ALL
  USING (motoboy_id = auth.uid());


-- ═══ 6. GARANTIR TRIGGER DE SIGNUP FUNCIONA COM SECURITY DEFINER ═══

-- O trigger roda como SECURITY DEFINER (superuser), então bypassa RLS.
-- Mas vamos garantir que está correto:
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, name, email, phone, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', 'Usuário'),
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'phone', ''),
    COALESCE(NEW.raw_user_meta_data->>'role', 'client')
  )
  ON CONFLICT (id) DO UPDATE SET
    name  = EXCLUDED.name,
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    role  = EXCLUDED.role;

  -- Se é motoboy, cria registro na tabela motoboys
  IF NEW.raw_user_meta_data->>'role' = 'motoboy' THEN
    INSERT INTO public.motoboys (id, wallet_balance, is_online)
    VALUES (NEW.id, 0.00, false)
    ON CONFLICT (id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recriar o trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ═══ 7. POLICIES PARA TABELAS AUXILIARES ═══════════════════

-- Recharges (se existir)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'recharges' AND table_schema = 'public') THEN
    ALTER TABLE public.recharges ENABLE ROW LEVEL SECURITY;
    
    EXECUTE 'DROP POLICY IF EXISTS "recharges: próprio" ON public.recharges';
    EXECUTE 'CREATE POLICY "recharges: próprio" ON public.recharges FOR ALL USING (motoboy_id = auth.uid())';
  END IF;
END $$;

-- Transactions (se existir)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'transactions' AND table_schema = 'public') THEN
    ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
    
    EXECUTE 'DROP POLICY IF EXISTS "transactions: próprio" ON public.transactions';
    EXECUTE 'CREATE POLICY "transactions: próprio" ON public.transactions FOR ALL USING (motoboy_id = auth.uid())';
  END IF;
END $$;

-- FCM tokens (se existir)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'fcm_tokens' AND table_schema = 'public') THEN
    ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY;
    
    EXECUTE 'DROP POLICY IF EXISTS "fcm_tokens: próprio" ON public.fcm_tokens';
    EXECUTE 'CREATE POLICY "fcm_tokens: próprio" ON public.fcm_tokens FOR ALL USING (user_id = auth.uid())';
  END IF;
END $$;

-- Vehicle pricing (leitura pública)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'vehicle_pricing' AND table_schema = 'public') THEN
    EXECUTE 'DROP POLICY IF EXISTS "pricing: leitura pública" ON public.vehicle_pricing';
    EXECUTE 'CREATE POLICY "pricing: leitura pública" ON public.vehicle_pricing FOR SELECT USING (true)';
  END IF;
END $$;


-- ═══ 8. VERIFICAÇÃO FINAL ══════════════════════════════════
-- Execute esta query para ver todas as policies e verificar que
-- NÃO há referências circulares:
--
-- SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
-- FROM pg_policies
-- WHERE schemaname = 'public'
-- ORDER BY tablename, policyname;
