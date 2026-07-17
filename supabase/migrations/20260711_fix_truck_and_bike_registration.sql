-- ============================================================
-- Correção definitiva no trigger de cadastro de entregadores
--   - Mapeia 'truck' para 'caminhao'
--   - Converte strings vazias ('') para NULL via NULLIF
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- Cria o usuário com todos os dados básicos da conta
  INSERT INTO public.users (
    id,
    name,
    email,
    phone,
    role,
    client_type,
    document,
    terms_accepted_at,
    terms_version,
    terms_role,
    privacy_accepted_at,
    privacy_version
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', 'Usuário'),
    NEW.email,
    COALESCE(NULLIF(NEW.raw_user_meta_data->>'phone', ''), NULL),
    COALESCE(NEW.raw_user_meta_data->>'role', 'client'),
    NULLIF(NEW.raw_user_meta_data->>'client_type', ''),
    NULLIF(NEW.raw_user_meta_data->>'document', ''),
    NULLIF(NEW.raw_user_meta_data->>'terms_accepted_at', '')::TIMESTAMPTZ,
    NULLIF(NEW.raw_user_meta_data->>'terms_version', ''),
    NULLIF(NEW.raw_user_meta_data->>'terms_role', ''),
    NULLIF(NEW.raw_user_meta_data->>'privacy_accepted_at', '')::TIMESTAMPTZ,
    NULLIF(NEW.raw_user_meta_data->>'privacy_version', '')
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    role = EXCLUDED.role,
    client_type = EXCLUDED.client_type,
    document = EXCLUDED.document,
    terms_accepted_at = COALESCE(
      EXCLUDED.terms_accepted_at,
      public.users.terms_accepted_at
    ),
    terms_version = COALESCE(
      EXCLUDED.terms_version,
      public.users.terms_version
    ),
    terms_role = COALESCE(EXCLUDED.terms_role, public.users.terms_role),
    privacy_accepted_at = COALESCE(
      EXCLUDED.privacy_accepted_at,
      public.users.privacy_accepted_at
    ),
    privacy_version = COALESCE(
      EXCLUDED.privacy_version,
      public.users.privacy_version
    );

  -- Se for entregador
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
      NULLIF(NEW.raw_user_meta_data->>'cpf', ''),
      NULLIF(NEW.raw_user_meta_data->>'rg_number', ''),
      NULLIF(NEW.raw_user_meta_data->>'vehicle_plate', ''),
      CASE
        WHEN NEW.raw_user_meta_data->>'vehicle_category' = 'truck' THEN 'caminhao'
        ELSE COALESCE(NULLIF(NEW.raw_user_meta_data->>'vehicle_category', ''), 'motoboy')
      END,
      NULLIF(NEW.raw_user_meta_data->>'vehicle_model', ''),
      CASE
        WHEN NEW.raw_user_meta_data->>'vehicle_year' IS NOT NULL
          AND NULLIF(NEW.raw_user_meta_data->>'vehicle_year', '') IS NOT NULL
          AND NEW.raw_user_meta_data->>'vehicle_year' ~ '^\d+$'
        THEN (NEW.raw_user_meta_data->>'vehicle_year')::INTEGER
        ELSE NULL
      END,
      NULLIF(NEW.raw_user_meta_data->>'cnh_number', ''),
      NULLIF(NEW.raw_user_meta_data->>'cnh_category', ''),
      CASE
        WHEN NEW.raw_user_meta_data->>'cnh_expiration_date' IS NOT NULL
          AND NULLIF(NEW.raw_user_meta_data->>'cnh_expiration_date', '') IS NOT NULL
        THEN (NEW.raw_user_meta_data->>'cnh_expiration_date')::TIMESTAMPTZ
        ELSE NULL
      END,
      NULLIF(NEW.raw_user_meta_data->>'address_zip_code', ''),
      NULLIF(NEW.raw_user_meta_data->>'address_number', ''),
      NULLIF(NEW.raw_user_meta_data->>'address_complement', ''),
      NULLIF(NEW.raw_user_meta_data->>'address_label', ''),
      'pending_documents'
    )
    ON CONFLICT (id) DO UPDATE SET
      cpf = COALESCE(EXCLUDED.cpf, public.motoboys.cpf),
      rg_number = COALESCE(EXCLUDED.rg_number, public.motoboys.rg_number),
      vehicle_plate = COALESCE(
        EXCLUDED.vehicle_plate,
        public.motoboys.vehicle_plate
      ),
      vehicle_category = COALESCE(
        EXCLUDED.vehicle_category,
        public.motoboys.vehicle_category
      ),
      vehicle_model = COALESCE(
        EXCLUDED.vehicle_model,
        public.motoboys.vehicle_model
      ),
      vehicle_year = COALESCE(EXCLUDED.vehicle_year, public.motoboys.vehicle_year),
      cnh_number = COALESCE(EXCLUDED.cnh_number, public.motoboys.cnh_number),
      cnh_category = COALESCE(
        EXCLUDED.cnh_category,
        public.motoboys.cnh_category
      ),
      cnh_expiration_date = COALESCE(
        EXCLUDED.cnh_expiration_date,
        public.motoboys.cnh_expiration_date
      ),
      address_zip_code = COALESCE(
        EXCLUDED.address_zip_code,
        public.motoboys.address_zip_code
      ),
      address_number = COALESCE(
        EXCLUDED.address_number,
        public.motoboys.address_number
      ),
      address_complement = COALESCE(
        EXCLUDED.address_complement,
        public.motoboys.address_complement
      ),
      address_label = COALESCE(
        EXCLUDED.address_label,
        public.motoboys.address_label
      );
  ELSE
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
