-- ═══════════════════════════════════════════════════════════════════════════
-- UrbGo — Diagnóstico do pipeline de notificações
-- Cole e rode cada bloco separadamente no SQL Editor
-- ═══════════════════════════════════════════════════════════════════════════


-- ── BLOCO 1: O motoboy tem fcm_token e atende os critérios? ─────────────
SELECT
  m.id,
  u.email,
  u.fcm_token IS NOT NULL        AS tem_token,
  LEFT(u.fcm_token, 20)          AS token_inicio,
  m.is_online,
  m.last_active_at,
  m.inactivity_notif_level,
  ROUND(EXTRACT(EPOCH FROM (NOW() - m.last_active_at)) / 3600, 1) AS horas_inativo
FROM motoboys m
JOIN users u ON u.id = m.id
WHERE m.id = 'c3c26d6c-2f4d-4f1d-910f-6f65a628e4ed';


-- ── BLOCO 2: pg_net está habilitado? ────────────────────────────────────
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_net';


-- ── BLOCO 3: Últimas chamadas HTTP feitas pelo pg_net ───────────────────
-- (mostra se urbgo_send_push chegou a disparar algum request)
SELECT
  id,
  status_code,
  LEFT(content::TEXT, 200) AS resposta,
  created
FROM net._http_response
ORDER BY created DESC
LIMIT 10;


-- ── BLOCO 4: Testar urbgo_send_push diretamente com o token real ────────
-- (substitua o token pelo valor de fcm_token da query do BLOCO 1)
SELECT public.urbgo_send_push(
  '<FCM_TOKEN_DO_BLOCO_1>',
  'Teste direto SQL',
  'Se chegar aqui, urbgo_send_push está OK',
  '{"type":"test"}'::jsonb
);

-- Aguarde 3s e verifique a resposta do pg_net:
SELECT
  id,
  status_code,
  LEFT(content::TEXT, 300) AS resposta
FROM net._http_response
ORDER BY created DESC
LIMIT 3;


-- ── BLOCO 5: O corpo da função tem o service_role_key real ou placeholder?
SELECT LEFT(prosrc, 400) AS fonte_da_funcao
FROM pg_proc
WHERE proname = 'urbgo_send_push';
