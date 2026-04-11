import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY")!;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  try {
    const { token, title, body, data } = await req.json();

    if (!token || !title) {
      return new Response(
        JSON.stringify({ error: "token e title são obrigatórios" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const res = await fetch("https://fcm.googleapis.com/fcm/send", {
      method: "POST",
      headers: {
        "Authorization": `key=${FCM_SERVER_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        to: token,
        priority: "high",
        notification: {
          title,
          body: body ?? "",
          sound: "default",
        },
        data: data ?? {},
      }),
    });

    const result = await res.json();
    console.log("FCM response:", JSON.stringify(result));

    return new Response(JSON.stringify(result), {
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (err) {
    console.error("send-push error:", err);
    return new Response(
      JSON.stringify({ error: "Erro ao enviar push" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
