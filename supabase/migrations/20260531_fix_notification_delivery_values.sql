-- ============================================================
-- Padroniza valores monetarios das notificacoes de entrega
-- - Arredonda valor liquido para 2 casas
-- - Formata decimal no padrao pt-BR (virgula)
-- ============================================================

CREATE OR REPLACE FUNCTION public.process_delivery_notification_queue(
  p_delivery_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r                  RECORD;
  v_delivery_val     NUMERIC;
  v_delivery_val_text TEXT;
  v_body             TEXT;
BEGIN
  FOR r IN
    SELECT
      t.id,
      t.delivery_id,
      t.distance_km,
      u.fcm_token,
      d.value,
      d.commission
    FROM public.delivery_notification_targets t
    JOIN public.deliveries d ON d.id = t.delivery_id
    JOIN public.users u      ON u.id = t.motoboy_id
    WHERE t.sent_at IS NULL
      AND t.available_from <= NOW()
      AND d.status = 'pending'
      AND d.motoboy_id IS NULL
      AND u.fcm_token IS NOT NULL
      AND (p_delivery_id IS NULL OR t.delivery_id = p_delivery_id)
    ORDER BY t.available_from ASC, t.distance_km ASC
  LOOP
    v_delivery_val := ROUND(r.value::NUMERIC, 2);
    v_delivery_val_text := REPLACE(
      to_char(v_delivery_val, 'FM999999990.00'),
      '.',
      ','
    );
    v_body := 'Voce recebe R$ ' || v_delivery_val_text
      || ' • a ' || r.distance_km::TEXT || ' km da coleta';

    PERFORM public.arkgo_send_push(
      r.fcm_token,
      'Nova corrida disponivel! 📦',
      v_body,
      jsonb_build_object(
        'deliveryId', r.delivery_id::TEXT,
        'role', 'motoboy',
        'type', 'new_delivery'
      )
    );

    UPDATE public.delivery_notification_targets
    SET sent_at = NOW()
    WHERE id = r.id;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_delivery_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_client_token     TEXT;
  v_motoboy_token    TEXT;
  v_motoboy_name     TEXT;
  v_delivery_val     NUMERIC;
  v_delivery_val_text TEXT;
BEGIN
  BEGIN
    IF OLD.status = NEW.status THEN
      RETURN NEW;
    END IF;

    SELECT fcm_token INTO v_client_token
    FROM users WHERE id = NEW.client_id;

    IF NEW.motoboy_id IS NOT NULL THEN
      SELECT u.fcm_token, u.name
      INTO   v_motoboy_token, v_motoboy_name
      FROM   users u WHERE u.id = NEW.motoboy_id;
    END IF;

    v_delivery_val := ROUND(NEW.value::NUMERIC, 2);
    v_delivery_val_text := REPLACE(
      to_char(v_delivery_val, 'FM999999990.00'),
      '.',
      ','
    );

    IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
      PERFORM public.arkgo_send_push(
        v_client_token,
        'Entregador a caminho!',
        COALESCE(v_motoboy_name, 'Seu entregador') || ' aceitou o pedido.',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'accepted')
      );

    ELSIF NEW.status = 'in_progress' AND OLD.status = 'accepted' THEN
      PERFORM public.arkgo_send_push(
        v_client_token,
        'Pacote coletado!',
        'Seu pedido está a caminho do destino.',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'in_progress')
      );

    ELSIF NEW.status = 'completed' AND OLD.status = 'in_progress' THEN
      PERFORM public.arkgo_send_push(
        v_client_token,
        'Entrega concluída! ✓',
        'Seu pedido chegou com sucesso. Avalie seu entregador!',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'completed')
      );
      PERFORM public.arkgo_send_push(
        v_motoboy_token,
        'Corrida finalizada!',
        'Você ganhou R$ ' || v_delivery_val_text || ' nesta entrega.',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'motoboy', 'type', 'run_completed')
      );

    ELSIF NEW.status = 'cancelled' THEN
      PERFORM public.arkgo_send_push(
        v_client_token,
        'Entrega cancelada',
        'Sua entrega foi cancelada.',
        jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'client', 'type', 'cancelled')
      );
      IF v_motoboy_token IS NOT NULL THEN
        PERFORM public.arkgo_send_push(
          v_motoboy_token,
          'Corrida cancelada',
          'A entrega foi cancelada pelo cliente.',
          jsonb_build_object('deliveryId', NEW.id::TEXT, 'role', 'motoboy', 'type', 'run_cancelled')
        );
      END IF;
    END IF;

  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN NEW;
END;
$$;
