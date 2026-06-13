-- ════════════════════════════════════════════════════════════════════════════
-- Notificações push para mensagens do chat entre cliente e entregador
--
-- Depende de: arkgo_send_push() já criada pela migration anterior
--             (20260613_fix_delivery_notification_flow.sql)
-- ════════════════════════════════════════════════════════════════════════════


-- ── Função: notifica a outra parte quando uma mensagem é enviada ─────────────

CREATE OR REPLACE FUNCTION public.notify_new_chat_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_client_id      UUID;
  v_motoboy_id     UUID;
  v_sender_name    TEXT;
  v_recipient_token TEXT;
  v_recipient_role  TEXT;
  v_preview        TEXT;
BEGIN
  -- Busca os participantes da entrega
  SELECT client_id, motoboy_id
  INTO   v_client_id, v_motoboy_id
  FROM   public.deliveries
  WHERE  id = NEW.delivery_id;

  -- Sem entregador aceito ainda → não há com quem falar
  IF v_motoboy_id IS NULL THEN RETURN NEW; END IF;

  -- Nome de quem enviou (para o título da notificação)
  SELECT name INTO v_sender_name
  FROM   public.users WHERE id = NEW.sender_id;

  -- Preview: primeiros 80 caracteres da mensagem
  v_preview := LEFT(NEW.content, 80);
  IF char_length(NEW.content) > 80 THEN
    v_preview := v_preview || '…';
  END IF;

  IF NEW.sender_role = 'client' THEN
    -- Cliente enviou → notifica o entregador
    SELECT fcm_token INTO v_recipient_token
    FROM   public.users WHERE id = v_motoboy_id;
    v_recipient_role := 'motoboy';
  ELSE
    -- Entregador enviou → notifica o cliente
    SELECT fcm_token INTO v_recipient_token
    FROM   public.users WHERE id = v_client_id;
    v_recipient_role := 'client';
  END IF;

  PERFORM public.arkgo_send_push(
    v_recipient_token,
    '💬 ' || COALESCE(v_sender_name, 'Nova mensagem'),
    v_preview,
    jsonb_build_object(
      'deliveryId', NEW.delivery_id::TEXT,
      'role',       v_recipient_role,
      'type',       'new_message'
    )
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[notify_new_chat_message] Erro: %', SQLERRM;
  RETURN NEW;
END;
$$;


-- ── Trigger: dispara após cada mensagem inserida ─────────────────────────────

DROP TRIGGER IF EXISTS trg_notify_new_chat_message ON public.delivery_messages;

CREATE TRIGGER trg_notify_new_chat_message
  AFTER INSERT ON public.delivery_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_new_chat_message();


-- ── Verificação ──────────────────────────────────────────────────────────────

SELECT
  tgname   AS trigger,
  tgenabled AS enabled
FROM pg_trigger
WHERE tgrelid = 'public.delivery_messages'::regclass;
