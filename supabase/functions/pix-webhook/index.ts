import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_TOKEN = Deno.env.get("ASAAS_WEBHOOK_TOKEN")!;

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

  console.log(
    `Recarga confirmada: R$${recharge.amount} para ${recharge.motoboy_id}`
  );
  return new Response("ok");
});
