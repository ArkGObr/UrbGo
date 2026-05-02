ALTER TABLE public.motoboys
  ADD COLUMN IF NOT EXISTS address_zip_code TEXT,
  ADD COLUMN IF NOT EXISTS address_number TEXT,
  ADD COLUMN IF NOT EXISTS address_complement TEXT,
  ADD COLUMN IF NOT EXISTS address_label TEXT;

UPDATE public.motoboys
SET approval_status = CASE
  WHEN identity_document_url IS NOT NULL
    AND selfie_with_document_url IS NOT NULL
    AND address_zip_code IS NOT NULL
    AND address_number IS NOT NULL
    AND address_label IS NOT NULL
    AND (
      vehicle_category = 'bike'
      OR vehicle_document_url IS NOT NULL
    )
    AND (
      vehicle_category NOT IN ('mototaxi', 'van', 'truck')
      OR additional_permit_url IS NOT NULL
    )
  THEN 'pending_review'
  ELSE 'pending_documents'
END;
