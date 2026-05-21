-- ═══════════════════════════════════════════════════════════════════════════
-- ArkGo — Recria arkgo_send_push com URL e service_role_key embutidos
--
-- Execute no Supabase SQL Editor APÓS substituir <SERVICE_ROLE_KEY> pelo
-- valor real em: Dashboard → Settings → API → service_role (clica Reveal)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.arkgo_send_push(
  p_token TEXT,
  p_title TEXT,
  p_body  TEXT,
  p_data  JSONB DEFAULT '{}'::JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_token IS NULL OR p_token = '' THEN RETURN; END IF;

  PERFORM net.http_post(
    url     := 'https://lpapiwkfqghdfkekwjnt.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer <SERVICE_ROLE_KEY>'
    ),
    body    := jsonb_build_object(
      'token', p_token,
      'title', p_title,
      'body',  p_body,
      'data',  p_data
    )
  );
END;
$$;

-- Confirma que a função foi recriada
SELECT prosrc IS NOT NULL AS ok FROM pg_proc WHERE proname = 'arkgo_send_push';
