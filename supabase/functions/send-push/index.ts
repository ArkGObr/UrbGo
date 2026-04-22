import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

// ─────────────────────────────────────────────────────────────────────────────
// FCM HTTP v1 API (a API legada foi descontinuada em junho/2024)
// Env vars necessárias:
//   FIREBASE_SERVICE_ACCOUNT  →  JSON completo do service account do Firebase
// ─────────────────────────────────────────────────────────────────────────────

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

// Converte PEM para DER (ArrayBuffer) para uso com Web Crypto API
function pemToDer(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----\n?/, "")
    .replace(/-----END PRIVATE KEY-----\n?/, "")
    .replace(/\n/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function b64url(input: string | ArrayBuffer): string {
  let str: string;
  if (typeof input === "string") {
    str = btoa(unescape(encodeURIComponent(input)));
  } else {
    str = btoa(String.fromCharCode(...new Uint8Array(input)));
  }
  return str.replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

// Obtém token OAuth2 de curta duração usando JWT assinado com chave do service account
async function getOAuthToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: sa.token_uri ?? "https://oauth2.googleapis.com/token",
      exp: now + 3600,
      iat: now,
    }),
  );

  const sigInput = `${header}.${payload}`;
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
    new TextEncoder().encode(sigInput),
  );

  const jwt = `${sigInput}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body:
      `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  const tokenData = await res.json();
  if (!tokenData.access_token) {
    throw new Error(`OAuth2 falhou: ${JSON.stringify(tokenData)}`);
  }
  return tokenData.access_token;
}

// Envia mensagem via FCM HTTP v1
async function sendToToken(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<unknown> {
  // Garantir que todos os valores de data são strings (requisito FCM v1)
  const safeData: Record<string, string> = {};
  for (const [k, v] of Object.entries(data ?? {})) {
    safeData[k] = String(v);
  }

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "urbgo_channel",
              notification_priority: "PRIORITY_HIGH",
              default_sound: true,
              default_vibrate_timings: true,
              default_light_settings: true,
            },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: "default", badge: 1 } },
          },
          data: safeData,
        },
      }),
    },
  );
  return res.json();
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!saJson) throw new Error("FIREBASE_SERVICE_ACCOUNT não configurada");

    const sa: ServiceAccount = JSON.parse(saJson);
    const accessToken = await getOAuthToken(sa);

    const { token, tokens, title, body, data } = await req.json();

    if (!title) {
      return new Response(
        JSON.stringify({ error: "title é obrigatório" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const targets: string[] = token
      ? [token]
      : Array.isArray(tokens)
      ? tokens
      : [];

    if (targets.length === 0) {
      return new Response(
        JSON.stringify({ error: "token ou tokens são obrigatórios" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const results = await Promise.allSettled(
      targets.map((t) =>
        sendToToken(accessToken, sa.project_id, t, title, body ?? "", data ?? {})
      ),
    );

    const summary = results.map((r) =>
      r.status === "fulfilled" ? r.value : { error: String(r.reason) }
    );

    console.log(`FCM v1: ${targets.length} token(s)`, JSON.stringify(summary));

    return new Response(
      JSON.stringify({ sent: targets.length, results: summary }),
      { headers: { "Content-Type": "application/json", ...CORS_HEADERS } },
    );
  } catch (err) {
    console.error("send-push error:", err);
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json", ...CORS_HEADERS } },
    );
  }
});
