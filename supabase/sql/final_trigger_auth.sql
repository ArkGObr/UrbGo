-- ═══════════════════════════════════════════════════════════════
-- URBGO — Otimização Definitiva do Trigger (Ignorando RLS Blockers)
-- Execute este bloco completo no Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- Cria o usuário com todos os dados básicos da conta
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

  -- Se for entregador, cria e já guarda todos os dados da moto! (Isso burla o RLS)
  IF NEW.raw_user_meta_data->>'role' = 'motoboy' THEN
    INSERT INTO public.motoboys (
      id, wallet_balance, is_online, 
      vehicle_plate, vehicle_category, vehicle_model, vehicle_year
    )
    VALUES (
      NEW.id, 
      0.00, 
      false,
      NEW.raw_user_meta_data->>'vehicle_plate',
      NEW.raw_user_meta_data->>'vehicle_category',
      NEW.raw_user_meta_data->>'vehicle_model',
      (NEW.raw_user_meta_data->>'vehicle_year')::integer
    )
    ON CONFLICT (id) DO UPDATE SET
      vehicle_plate = EXCLUDED.vehicle_plate,
      vehicle_category = EXCLUDED.vehicle_category,
      vehicle_model = EXCLUDED.vehicle_model,
      vehicle_year = EXCLUDED.vehicle_year;
  END IF;

  -- Se for cliente
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
  RAISE WARNING 'Falha inesperada no trigger: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
