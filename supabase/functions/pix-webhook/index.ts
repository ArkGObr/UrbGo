import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PAGARME_WEBHOOK_SECRET = Deno.env.get("PAGARME_WEBHOOK_SECRET")!;
const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY");

// Verifica assinatura HMAC-SHA256 enviada pelo Pagar.me no header x-pagarme-signature
async function verifySignature(
  rawBody: string,
  signatureHeader: string,
): Promise<boolean> {
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
    const res = await fetch("https://fcm.googleapis.com/fcm/send", {
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
    const result = await res.json();
    console.log("FCM recharge push:", JSON.stringify(result));
  } catch (err) {
    console.error("Erro ao enviar push de recarga:", err);
  }
}

serve(async (req: Request) => {
  const rawBody = await req.text();

  // Verificar assinatura do Pagar.me
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

  console.log("Pagar.me webhook:", event.type);

  // Só processar pagamentos confirmados
  if (event.type !== "charge.paid") {
    return new Response("ignored");
  }

  const chargeId: string = event.data?.id;
  if (!chargeId) return new Response("no charge id");

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // 1. Buscar recarga pendente pelo gateway_id (charge.id do Pagar.me)
  const { data: recharge, error } = await supabase
    .from("recharges")
    .select("*")
    .eq("gateway_id", chargeId)
    .eq("gateway_status", "pending")
    .single();

  if (error || !recharge) {
    console.log("Recarga não encontrada ou já processada:", chargeId);
    return new Response("not found");
  }

  // 2. Marcar recarga como confirmada
  await supabase
    .from("recharges")
    .update({
      gateway_status: "confirmed",
      confirmed_at: new Date().toISOString(),
    })
    .eq("id", recharge.id);

  // 3. Creditar saldo do motoboy
  const { data: motoboy } = await supabase
    .from("motoboys")
    .select("wallet_balance")
    .eq("id", recharge.motoboy_id)
    .single();

  const newBalance = (motoboy as any).wallet_balance + recharge.amount;

  await supabase
    .from("motoboys")
    .update({
      wallet_balance: newBalance,
      updated_at: new Date().toISOString(),
    })
    .eq("id", recharge.motoboy_id);

  // 4. Registrar transação
  await supabase.from("transactions").insert({
    motoboy_id: recharge.motoboy_id,
    type: "recharge",
    amount: recharge.amount,
    balance_after: newBalance,
    description: `Recarga PIX confirmada — R$${recharge.amount.toFixed(2)}`,
  });

  // 5. Push notification para o motoboy
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

  console.log(
    `Recarga confirmada: R$${recharge.amount} para ${recharge.motoboy_id}`,
  );
  return new Response("ok");
});
