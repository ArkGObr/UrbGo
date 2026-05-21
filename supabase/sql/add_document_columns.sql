-- ═══════════════════════════════════════════════════════════════
-- ARKGO — Atualização de Colunas do Cadastro de Clientes
-- Execute este bloco completo no Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Adiciona a coluna para separar pessoa física (cpf) e jurídica (cnpj)
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS client_type TEXT;

-- Adiciona a coluna para registrar o número do CPF ou CNPJ
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS document TEXT;

-- Verifica e garante as permissões para o App fazer inserções
DROP POLICY IF EXISTS "users: inserção própria" ON public.users;
CREATE POLICY "users: inserção própria"
  ON public.users FOR INSERT WITH CHECK (auth.uid() = id);

-- Verifica e garante as permissões para o App atualizar os próprios dados
DROP POLICY IF EXISTS "users: update próprio" ON public.users;
CREATE POLICY "users: update próprio"
  ON public.users FOR UPDATE USING (auth.uid() = id);
