import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_TOKEN = Deno.env.get("ASAAS_WEBHOOK_TOKEN")!;
const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY");

async function sendPushNotification(
  token: string,
  title: string,
  body: string,
  data: Record<string, string> = {}
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
  // Verificar token do webhook Asaas
  const token = req.headers.get("asaas-access-token");
  if (token !== WEBHOOK_TOKEN) {
    return new Response("Unauthorized", { status: 401 });
  }

  const event = await req.json();
  console.log("Webhook recebido:", event.event);

  // Só processar pagamentos confirmados
  if (
    event.event !== "PAYMENT_CONFIRMED" &&
    event.event !== "PAYMENT_RECEIVED"
  ) {
    return new Response("ignored");
  }

  const gatewayId = event.payment?.id;
  if (!gatewayId) return new Response("no payment id");

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // 1. Buscar recarga pendente pelo gateway_id
  const { data: recharge, error } = await supabase
    .from("recharges")
    .select("*")
    .eq("gateway_id", gatewayId)
    .eq("gateway_status", "pending")
    .single();

  if (error || !recharge) {
    console.log("Recarga não encontrada ou já processada:", gatewayId);
    return new Response("not found");
  }

  // 2. Atualizar recarga para confirmada
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

  // 5. Buscar FCM token do motoboy e enviar push notification
  const { data: motoboyUser } = await supabase
    .from("users")
    .select("fcm_token")
    .eq("id", recharge.motoboy_id)
    .single();

  if (motoboyUser?.fcm_token) {
    await sendPushNotification(
      motoboyUser.fcm_token,
      "Saldo recarregado! 💰",
      `R$ ${recharge.amount.toFixed(2)} foram adicionados à sua carteira.`,
      { role: "motoboy", type: "recharge", amount: String(recharge.amount) }
    );
  }

  console.log(
    `Recarga confirmada: R$${recharge.amount} para ${recharge.motoboy_id}`
  );
  return new Response("ok");
});
