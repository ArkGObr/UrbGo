-- ============================================================
-- Cadastro forte para entregadores
--   - documentos por categoria
--   - status de aprovacao
--   - bucket privado para documentos
--   - cascata de notificacao apenas para entregadores aprovados
-- ============================================================

ALTER TABLE public.motoboys
  ADD COLUMN IF NOT EXISTS cpf TEXT,
  ADD COLUMN IF NOT EXISTS cnh_number TEXT,
  ADD COLUMN IF NOT EXISTS cnh_category TEXT,
  ADD COLUMN IF NOT EXISTS cnh_expiration_date DATE,
  ADD COLUMN IF NOT EXISTS identity_document_url TEXT,
  ADD COLUMN IF NOT EXISTS selfie_with_document_url TEXT,
  ADD COLUMN IF NOT EXISTS address_proof_url TEXT,
  ADD COLUMN IF NOT EXISTS cnh_photo_url TEXT,
  ADD COLUMN IF NOT EXISTS vehicle_document_url TEXT,
  ADD COLUMN IF NOT EXISTS additional_permit_url TEXT,
  ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'pending_documents',
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
  ADD COLUMN IF NOT EXISTS documents_submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'motoboys_approval_status_check'
  ) THEN
    ALTER TABLE public.motoboys
      ADD CONSTRAINT motoboys_approval_status_check
      CHECK (approval_status IN ('pending_documents', 'pending_review', 'approved', 'rejected'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_motoboys_approval_status
  ON public.motoboys(approval_status, is_online);

UPDATE public.motoboys
SET approval_status = CASE
  WHEN identity_document_url IS NOT NULL
    AND selfie_with_document_url IS NOT NULL
    AND address_proof_url IS NOT NULL
    AND (
      vehicle_category = 'bike'
      OR (
        cnh_number IS NOT NULL
        AND cnh_category IS NOT NULL
        AND cnh_expiration_date IS NOT NULL
        AND cnh_photo_url IS NOT NULL
        AND vehicle_document_url IS NOT NULL
      )
    )
    AND (
      vehicle_category NOT IN ('mototaxi', 'van', 'truck')
      OR additional_permit_url IS NOT NULL
    )
  THEN 'pending_review'
  ELSE COALESCE(approval_status, 'pending_documents')
END
WHERE approval_status IS NULL OR approval_status = 'pending_documents';

INSERT INTO storage.buckets (id, name, public)
VALUES ('driver-documents', 'driver-documents', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "driver_docs_insert_own" ON storage.objects;
CREATE POLICY "driver_docs_insert_own"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'driver-documents'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );

DROP POLICY IF EXISTS "driver_docs_update_own" ON storage.objects;
CREATE POLICY "driver_docs_update_own"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'driver-documents'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  )
  WITH CHECK (
    bucket_id = 'driver-documents'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );

DROP POLICY IF EXISTS "driver_docs_select_own" ON storage.objects;
CREATE POLICY "driver_docs_select_own"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'driver-documents'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );

DROP POLICY IF EXISTS "driver_docs_delete_own" ON storage.objects;
CREATE POLICY "driver_docs_delete_own"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'driver-documents'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
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
    name = EXCLUDED.name,
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    role = EXCLUDED.role,
    client_type = EXCLUDED.client_type,
    document = EXCLUDED.document;

  IF NEW.raw_user_meta_data->>'role' = 'motoboy' THEN
    INSERT INTO public.motoboys (
      id,
      wallet_balance,
      is_online,
      cpf,
      vehicle_plate,
      vehicle_category,
      vehicle_model,
      vehicle_year,
      cnh_number,
      cnh_category,
      cnh_expiration_date,
      approval_status
    )
    VALUES (
      NEW.id,
      0.00,
      false,
      NEW.raw_user_meta_data->>'cpf',
      NEW.raw_user_meta_data->>'vehicle_plate',
      NEW.raw_user_meta_data->>'vehicle_category',
      NEW.raw_user_meta_data->>'vehicle_model',
      NULLIF(NEW.raw_user_meta_data->>'vehicle_year', '')::INTEGER,
      NEW.raw_user_meta_data->>'cnh_number',
      NEW.raw_user_meta_data->>'cnh_category',
      NULLIF(NEW.raw_user_meta_data->>'cnh_expiration_date', '')::DATE,
      'pending_documents'
    )
    ON CONFLICT (id) DO UPDATE SET
      cpf = EXCLUDED.cpf,
      vehicle_plate = EXCLUDED.vehicle_plate,
      vehicle_category = EXCLUDED.vehicle_category,
      vehicle_model = EXCLUDED.vehicle_model,
      vehicle_year = EXCLUDED.vehicle_year,
      cnh_number = EXCLUDED.cnh_number,
      cnh_category = EXCLUDED.cnh_category,
      cnh_expiration_date = EXCLUDED.cnh_expiration_date;
  END IF;

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

CREATE OR REPLACE FUNCTION public.notify_motoboys_new_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.delivery_notification_targets (
    delivery_id,
    motoboy_id,
    distance_km,
    wave,
    available_from
  )
  SELECT
    NEW.id,
    m.id,
    dist.distance_km,
    CASE
      WHEN dist.distance_km <= 3 THEN 0
      WHEN dist.distance_km <= 7 THEN 1
      WHEN dist.distance_km <= 11 THEN 2
      ELSE 3
    END AS wave,
    NOW() +
      CASE
        WHEN dist.distance_km <= 3 THEN INTERVAL '0 minute'
        WHEN dist.distance_km <= 7 THEN INTERVAL '2 minutes'
        WHEN dist.distance_km <= 11 THEN INTERVAL '4 minutes'
        ELSE INTERVAL '6 minutes'
      END AS available_from
  FROM public.motoboys m
  JOIN public.users u ON u.id = m.id
  CROSS JOIN LATERAL (
    SELECT public.urbgo_distance_km(
      m.current_lat,
      m.current_lng,
      NEW.pickup_lat,
      NEW.pickup_lng
    ) AS distance_km
  ) dist
  WHERE m.is_online = TRUE
    AND COALESCE(m.approval_status, 'pending_documents') = 'approved'
    AND u.fcm_token IS NOT NULL
    AND m.vehicle_category = NEW.vehicle_category
    AND m.current_lat IS NOT NULL
    AND m.current_lng IS NOT NULL
    AND dist.distance_km IS NOT NULL
    AND dist.distance_km <= 15
  ORDER BY dist.distance_km ASC
  LIMIT 100
  ON CONFLICT (delivery_id, motoboy_id) DO NOTHING;

  PERFORM public.process_delivery_notification_queue(NEW.id);
  RETURN NEW;
END;
$$;
