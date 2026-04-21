import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY")!;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const { token, tokens, title, body, data } = await req.json();

    if (!title) {
      return new Response(
        JSON.stringify({ error: "title é obrigatório" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Suporte a token único ou múltiplos tokens (multicast)
    const targets: string[] = token
      ? [token]
      : Array.isArray(tokens)
      ? tokens
      : [];

    if (targets.length === 0) {
      return new Response(
        JSON.stringify({ error: "token ou tokens são obrigatórios" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const results = await Promise.allSettled(
      targets.map((t) =>
        fetch("https://fcm.googleapis.com/fcm/send", {
          method: "POST",
          headers: {
            Authorization: `key=${FCM_SERVER_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            to: t,
            priority: "high",
            notification: {
              title,
              body: body ?? "",
              sound: "default",
              android_channel_id: "urbgo_channel",
            },
            android: {
              priority: "high",
              notification: {
                channel_id: "urbgo_channel",
                sound: "default",
                default_sound: true,
              },
            },
            apns: {
              payload: {
                aps: { sound: "default", badge: 1 },
              },
            },
            data: { ...(data ?? {}), click_action: "FLUTTER_NOTIFICATION_CLICK" },
          }),
        }).then((r) => r.json())
      )
    );

    const summary = results.map((r) =>
      r.status === "fulfilled" ? r.value : { error: r.reason }
    );

    console.log("FCM results:", JSON.stringify(summary));

    return new Response(JSON.stringify({ sent: targets.length, results: summary }), {
      headers: { "Content-Type": "application/json", ...CORS_HEADERS },
    });
  } catch (err) {
    console.error("send-push error:", err);
    return new Response(
      JSON.stringify({ error: "Erro ao enviar push" }),
      { status: 500, headers: { "Content-Type": "application/json", ...CORS_HEADERS } }
    );
  }
});
