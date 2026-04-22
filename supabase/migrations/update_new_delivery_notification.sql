-- Atualiza notificação de nova entrega: remove o valor e usa frase motivadora
CREATE OR REPLACE FUNCTION public.notify_motoboys_new_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r        RECORD;
  messages TEXT[] := ARRAY[
    'Corra, ela pode ser sua! 🏍️',
    'Aceite antes que alguém pegue! ⚡',
    'Abra o app e garanta a corrida! 🔥',
    'Oportunidade de ganho esperando por você! 💰',
    'Tem corrida na sua região — seja o primeiro! 🚀'
  ];
  body_msg TEXT;
BEGIN
  body_msg := messages[1 + floor(random() * array_length(messages, 1))::INT];

  FOR r IN
    SELECT u.fcm_token
    FROM   motoboys m
    JOIN   users u ON u.id = m.id
    WHERE  u.fcm_token IS NOT NULL
      AND  m.vehicle_category = NEW.vehicle_category
    LIMIT 50
  LOOP
    PERFORM public.urbgo_send_push(
      r.fcm_token,
      'Nova corrida disponível! 📦',
      body_msg,
      jsonb_build_object(
        'deliveryId', NEW.id::TEXT,
        'role',       'motoboy',
        'type',       'new_delivery'
      )
    );
  END LOOP;

  RETURN NEW;
END;
$$;
