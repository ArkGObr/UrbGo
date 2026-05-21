-- ═══════════════════════════════════════════════════════════════
-- ARKGO — Correção de Bugs no Schema
-- Execute este bloco completo no Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Corrigir a tabela users para aceitar phone NULL → NOT NULL vai false ──
-- O phone vinha nulo do trigger e causava erro.
-- Solução: permitir null temporariamente, depois o app atualiza via update

ALTER TABLE public.users
  ALTER COLUMN phone DROP NOT NULL;

-- ─── 2. Recriar o trigger handle_new_user com phone incluído ──────────────────
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

  IF NEW.raw_user_meta_data->>'role' = 'motoboy' THEN
    INSERT INTO public.motoboys (id, wallet_balance, is_online)
    VALUES (NEW.id, 0.00, false)
    ON CONFLICT (id) DO NOTHING;
  ELSE
    -- Garante registro em clients se tabela existir
    -- (caso não exista, o INSERT é ignorado)
    BEGIN
      INSERT INTO public.clients (id)
      VALUES (NEW.id)
      ON CONFLICT (id) DO NOTHING;
    EXCEPTION WHEN undefined_table THEN
      NULL; -- tabela clients não existe, ok
    END;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recriar o trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ─── 3. Adicionar policy de INSERT para users (necessário para upsert do app) ─
DROP POLICY IF EXISTS "users: inserção própria" ON public.users;
CREATE POLICY "users: inserção própria"
  ON public.users FOR INSERT WITH CHECK (auth.uid() = id);

-- ─── 4. Adicionar policy de INSERT para motoboys ──────────────────────────────
DROP POLICY IF EXISTS "motoboys: inserção própria" ON public.motoboys;
CREATE POLICY "motoboys: inserção própria"
  ON public.motoboys FOR INSERT WITH CHECK (auth.uid() = id);

-- ─── 5. Habilitar email confirmação opcional (execute se quiser login sem confirmar email) ─
-- No painel Supabase: Authentication > Settings > desabilite "Enable email confirmations"
-- OU execute (requer Supabase CLI e acesso admin):
-- UPDATE auth.config SET enable_confirmations = false;

-- ─── 6. Verificar usuários criados sem registro em users (limpeza) ────────────
-- Liste usuários órfãos (auth mas sem users):
-- SELECT au.id, au.email FROM auth.users au
-- LEFT JOIN public.users u ON u.id = au.id
-- WHERE u.id IS NULL;

-- ─── 7. Garantir que recharges tem a coluna confirmed_at opcional ─────────────
ALTER TABLE public.recharges
  ALTER COLUMN confirmed_at DROP NOT NULL;
