-- ============================================================
-- Alta Prioridade:
--   A2. Chat cliente ↔ motoboy
--   A3. Parada extra (multi-stop simplificado)
--   A4. Foto de confirmação de entrega
--   A5. Regras de cancelamento (aceito < 5 min)
-- ============================================================

-- ── A2: Chat ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.delivery_messages (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id  UUID        NOT NULL REFERENCES public.deliveries(id) ON DELETE CASCADE,
  sender_id    UUID        NOT NULL REFERENCES public.users(id),
  sender_role  TEXT        NOT NULL CHECK (sender_role IN ('client', 'motoboy')),
  content      TEXT        NOT NULL CHECK (char_length(content) BETWEEN 1 AND 500),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS delivery_messages_delivery_created_idx
  ON public.delivery_messages(delivery_id, created_at);

ALTER TABLE public.delivery_messages ENABLE ROW LEVEL SECURITY;

-- Participantes da entrega podem ler mensagens
CREATE POLICY "chat_select" ON public.delivery_messages FOR SELECT
  USING (
    auth.uid() IN (
      SELECT client_id  FROM public.deliveries WHERE id = delivery_id
      UNION
      SELECT motoboy_id FROM public.deliveries WHERE id = delivery_id AND motoboy_id IS NOT NULL
    )
  );

-- Participantes da entrega podem enviar mensagens (apenas como eles mesmos)
CREATE POLICY "chat_insert" ON public.delivery_messages FOR INSERT
  WITH CHECK (
    auth.uid() = sender_id
    AND auth.uid() IN (
      SELECT client_id  FROM public.deliveries WHERE id = delivery_id
      UNION
      SELECT motoboy_id FROM public.deliveries WHERE id = delivery_id AND motoboy_id IS NOT NULL
    )
  );

-- Realtime para o canal de mensagens
ALTER PUBLICATION supabase_realtime ADD TABLE public.delivery_messages;

-- ── A3: Parada extra ──────────────────────────────────────────
ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS extra_stop_address TEXT,
  ADD COLUMN IF NOT EXISTS extra_stop_lat     FLOAT8,
  ADD COLUMN IF NOT EXISTS extra_stop_lng     FLOAT8;

-- ── A4: Foto de confirmação ───────────────────────────────────
ALTER TABLE public.deliveries
  ADD COLUMN IF NOT EXISTS delivery_photo_url TEXT;

-- Bucket para fotos de entrega (criado via dashboard ou migrations de storage)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'delivery-photos',
  'delivery-photos',
  true,
  5242880, -- 5 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- RLS para o bucket: motoboy pode fazer upload; qualquer um pode ler
CREATE POLICY "motoboy_upload_delivery_photo"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'delivery-photos'
    AND auth.role() = 'authenticated'
  );

CREATE POLICY "public_read_delivery_photo"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'delivery-photos');
