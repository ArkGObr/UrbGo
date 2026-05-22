-- ═══════════════════════════════════════════════════════════════
-- ARKGO — Corrigir trigger para salvar todos os metadados do motoboy
-- Problema: trigger só salvava (id, wallet_balance, is_online).
-- Com confirmação de email, _saveMotoboyRegistration nunca era chamado,
-- então o motoboy ficava sem CPF, placa, endereço, etc.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- 1. Criar/atualizar registro na tabela users
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

  -- 2. Criar registro de motoboy com todos os metadados
  IF NEW.raw_user_meta_data->>'role' = 'motoboy' THEN
    INSERT INTO public.motoboys (
      id,
      wallet_balance,
      is_online,
      cpf,
      rg_number,
      vehicle_plate,
      vehicle_category,
      vehicle_model,
      vehicle_year,
      cnh_number,
      cnh_category,
      cnh_expiration_date,
      address_zip_code,
      address_number,
      address_complement,
      address_label,
      approval_status
    )
    VALUES (
      NEW.id,
      0.00,
      false,
      NEW.raw_user_meta_data->>'cpf',
      NEW.raw_user_meta_data->>'rg_number',
      NEW.raw_user_meta_data->>'vehicle_plate',
      COALESCE(NEW.raw_user_meta_data->>'vehicle_category', 'motoboy'),
      NEW.raw_user_meta_data->>'vehicle_model',
      CASE
        WHEN NEW.raw_user_meta_data->>'vehicle_year' IS NOT NULL
          AND NEW.raw_user_meta_data->>'vehicle_year' ~ '^\d+$'
        THEN (NEW.raw_user_meta_data->>'vehicle_year')::INTEGER
        ELSE NULL
      END,
      NEW.raw_user_meta_data->>'cnh_number',
      NEW.raw_user_meta_data->>'cnh_category',
      CASE
        WHEN NEW.raw_user_meta_data->>'cnh_expiration_date' IS NOT NULL
        THEN (NEW.raw_user_meta_data->>'cnh_expiration_date')::TIMESTAMPTZ
        ELSE NULL
      END,
      NEW.raw_user_meta_data->>'address_zip_code',
      NEW.raw_user_meta_data->>'address_number',
      NEW.raw_user_meta_data->>'address_complement',
      NEW.raw_user_meta_data->>'address_label',
      'pending_documents'
    )
    ON CONFLICT (id) DO UPDATE SET
      cpf                  = COALESCE(EXCLUDED.cpf, public.motoboys.cpf),
      rg_number            = COALESCE(EXCLUDED.rg_number, public.motoboys.rg_number),
      vehicle_plate        = COALESCE(EXCLUDED.vehicle_plate, public.motoboys.vehicle_plate),
      vehicle_category     = COALESCE(EXCLUDED.vehicle_category, public.motoboys.vehicle_category),
      vehicle_model        = COALESCE(EXCLUDED.vehicle_model, public.motoboys.vehicle_model),
      vehicle_year         = COALESCE(EXCLUDED.vehicle_year, public.motoboys.vehicle_year),
      cnh_number           = COALESCE(EXCLUDED.cnh_number, public.motoboys.cnh_number),
      cnh_category         = COALESCE(EXCLUDED.cnh_category, public.motoboys.cnh_category),
      cnh_expiration_date  = COALESCE(EXCLUDED.cnh_expiration_date, public.motoboys.cnh_expiration_date),
      address_zip_code     = COALESCE(EXCLUDED.address_zip_code, public.motoboys.address_zip_code),
      address_number       = COALESCE(EXCLUDED.address_number, public.motoboys.address_number),
      address_complement   = COALESCE(EXCLUDED.address_complement, public.motoboys.address_complement),
      address_label        = COALESCE(EXCLUDED.address_label, public.motoboys.address_label);

  ELSE
    -- Criar registro na tabela clients (se existir)
    BEGIN
      INSERT INTO public.clients (id)
      VALUES (NEW.id)
      ON CONFLICT (id) DO NOTHING;
    EXCEPTION WHEN undefined_table THEN
      NULL;
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
