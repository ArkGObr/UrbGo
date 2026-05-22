-- Função atômica para creditar recarga PIX.
-- Garante que:
--   1. A recarga só é processada UMA VEZ (gateway_status pending → confirmed)
--   2. O saldo é incrementado atomicamente (sem race condition)
-- Chamada tanto pelo check-pix-status quanto pelo pix-webhook.

CREATE OR REPLACE FUNCTION credit_wallet_if_pending(
  p_recharge_id  uuid,
  p_motoboy_id   uuid,
  p_amount       numeric
)
RETURNS TABLE(credited boolean, new_balance numeric)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_rows        integer;
  v_new_balance numeric;
BEGIN
  -- Marca a recarga como confirmada APENAS se ainda estiver pendente.
  -- Se outra chamada (webhook ou polling) já processou, v_rows = 0.
  UPDATE public.recharges
  SET gateway_status = 'confirmed',
      confirmed_at   = now()
  WHERE id             = p_recharge_id
    AND gateway_status = 'pending';

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    -- Já foi processado — retorna sem creditar novamente.
    RETURN QUERY SELECT false, 0::numeric;
    RETURN;
  END IF;

  -- Incrementa o saldo atomicamente com um único UPDATE.
  UPDATE public.motoboys
  SET wallet_balance = wallet_balance + p_amount,
      updated_at     = now()
  WHERE id = p_motoboy_id
  RETURNING wallet_balance INTO v_new_balance;

  RETURN QUERY SELECT true, v_new_balance;
END;
$$;
