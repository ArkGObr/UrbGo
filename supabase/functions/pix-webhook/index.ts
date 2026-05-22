import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PAGARME_WEBHOOK_SECRET = Deno.env.get("PAGARME_WEBHOOK_SECRET") ?? "";
const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY");

async function verifySignature(
  rawBody: string,
  signatureHeader: string,
): Promise<boolean> {
  if (!PAGARME_WEBHOOK_SECRET) return true; // sem secret configurado, aceita (dev)
  const sigHex = signatureHeader.replace(/^sha256=/, "");
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(PAGARME_WEBHOOK_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(rawBody));
  const macHex = Array.from(new Uint8Array(mac))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return macHex === sigHex;
}

async function sendPushNotification(
  token: string,
  title: string,
  body: string,
  data: Record<string, string> = {},
) {
  if (!FCM_SERVER_KEY || !token) return;
  try {
    await fetch("https://fcm.googleapis.com/fcm/send", {
      method: "POST",
      headers: {
        Authorization: `key=${FCM_SERVER_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        to: token,
        priority: "high",
        notification: { title, body, sound: "default" },
        data,
      }),
    });
  } catch (err) {
    console.error("Erro ao enviar push de recarga:", err);
  }
}

serve(async (req: Request) => {
  const rawBody = await req.text();

  const signature = req.headers.get("x-pagarme-signature") ?? "";
  const valid = await verifySignature(rawBody, signature);
  if (!valid) {
    console.warn("Webhook com assinatura inválida");
    return new Response("Unauthorized", { status: 401 });
  }

  let event: any;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  console.log("Pagar.me webhook event:", event.type);

  if (event.type !== "charge.paid") {
    return new Response("ignored");
  }

  const chargeId: string = event.data?.id;
  if (!chargeId) return new Response("no charge id");

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // 1. Buscar recarga pelo gateway_id
  const { data: recharge, error } = await supabase
    .from("recharges")
    .select("id, motoboy_id, amount, gateway_status")
    .eq("gateway_id", chargeId)
    .single();

  if (error || !recharge) {
    console.log("Recarga não encontrada para charge:", chargeId);
    return new Response("not found");
  }

  // 2. Creditar saldo atomicamente (evita duplo crédito com polling)
  const { data: creditRows, error: creditError } = await supabase.rpc(
    "credit_wallet_if_pending",
    {
      p_recharge_id: recharge.id,
      p_motoboy_id: recharge.motoboy_id,
      p_amount: recharge.amount,
    },
  );

  if (creditError) {
    console.error("Erro ao creditar via webhook:", creditError);
    return new Response("error", { status: 500 });
  }

  const result = creditRows?.[0];

  if (!result?.credited) {
    console.log("Recarga já creditada pelo polling:", recharge.id);
    return new Response("already processed");
  }

  const newBalance: number = result.new_balance;

  // 3. Registrar transação
  await supabase.from("transactions").insert({
    motoboy_id: recharge.motoboy_id,
    type: "recharge",
    amount: recharge.amount,
    balance_after: newBalance,
    description: `Recarga PIX confirmada — R$${recharge.amount.toFixed(2)}`,
  });

  // 4. Push notification
  const { data: motoboyUser } = await supabase
    .from("users")
    .select("fcm_token")
    .eq("id", recharge.motoboy_id)
    .single();

  if (motoboyUser?.fcm_token) {
    await sendPushNotification(
      motoboyUser.fcm_token,
      "Saldo recarregado!",
      `R$ ${recharge.amount.toFixed(2)} foram adicionados à sua carteira.`,
      { role: "motoboy", type: "recharge", amount: String(recharge.amount) },
    );
  }

  console.log(`Webhook: recarga R$${recharge.amount} creditada → saldo R$${newBalance}`);
  return new Response("ok");
});
