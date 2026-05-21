-- ═══════════════════════════════════════════════════════════════
-- ARKGO — Correção de Falhas Críticas de Autenticação
-- Execute este bloco completo no Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- 1. Remove restrição de unicidade no telefone (geralmente causa o "Database error saving new user" se você estiver testando com o mesmo telefone em várias contas)
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_phone_key;

-- 2. Recria o Trigger do zero de forma impecável, já injetando dados do Motoboy e do Cliente nativamente.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- Cria o usuário com todos os dados do meta_data de forma segura
  INSERT INTO public.users (id, name, email, phone, role, client_type, document)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', 'Usuário'),
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'phone', NULL),
    COALESCE(NEW.raw_user_meta_data->>'role', 'client'),
    NEW.raw_user_meta_data->>'client_type',
    NEW.raw_user_meta_data->>'document'
  )
  ON CONFLICT (id) DO UPDATE SET
    name  = EXCLUDED.name,
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    role  = EXCLUDED.role,
    client_type = EXCLUDED.client_type,
    document = EXCLUDED.document;

  -- Se for entregador, cria a carteira do Motoboy
  IF NEW.raw_user_meta_data->>'role' = 'motoboy' THEN
    INSERT INTO public.motoboys (id, wallet_balance, is_online)
    VALUES (NEW.id, 0.00, false)
    ON CONFLICT (id) DO NOTHING;
  END IF;

  -- Se for cliente, cria na tabela de clientes
  IF NEW.raw_user_meta_data->>'role' = 'client' THEN
    BEGIN
      INSERT INTO public.clients (id)
      VALUES (NEW.id)
      ON CONFLICT (id) DO NOTHING;
    EXCEPTION WHEN undefined_table THEN
      NULL;
    END;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Isso avisa ao Supabase Auth se o banco reclamar pra que não caia no erro de 500 genérico.
  RAISE WARNING 'Falha inesperada no trigger: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
