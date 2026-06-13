-- ============================================================
-- Corrige/garante a assinatura da funcao de push usada pelos
-- triggers de entrega.
--
-- Problema observado em producao:
--   function public.arkgo_send_push(text, unknown, text, jsonb) does not exist
--
-- Causa:
--   triggers de entrega passaram a depender de arkgo_send_push, mas em
--   alguns bancos a funcao nao existia mais, ou ficou com definicao
--   inconsistente. Isso faz o INSERT/UPDATE em deliveries falhar.
--
-- Solucao:
--   recriar a funcao com a assinatura canonica esperada pelos triggers e
--   fazer com que qualquer problema de configuracao de push nao bloqueie
--   a operacao principal da entrega.
-- ============================================================

CREATE OR REPLACE FUNCTION public.arkgo_send_push(
  p_token TEXT,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB DEFAULT '{}'::JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_url TEXT;
  v_key TEXT;
BEGIN
  IF p_token IS NULL OR btrim(p_token) = '' THEN
    RETURN;
  END IF;

  v_url := current_setting('app.supabase_url', true);
  v_key := current_setting('app.service_role_key', true);

  IF v_url IS NULL OR btrim(v_url) = '' OR v_key IS NULL OR btrim(v_key) = '' THEN
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body := jsonb_build_object(
      'token', p_token,
      'title', p_title,
      'body', p_body,
      'data', COALESCE(p_data, '{}'::JSONB)
    )
  );
EXCEPTION WHEN OTHERS THEN
  -- Push nunca pode bloquear criacao/atualizacao de entrega.
  NULL;
END;
$$;
