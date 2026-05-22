import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PAGARME_API_KEY = Deno.env.get("PAGARME_API_KEY") ?? "";
const PAGARME_URL = "https://api.pagar.me/core/v5";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

function pagarmeAuth(): string {
  return "Basic " + btoa(`${PAGARME_API_KEY}:`);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { rechargeId } = await req.json();

    if (!rechargeId) {
      return new Response(
        JSON.stringify({ error: "rechargeId obrigatório" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // 1. Buscar recarga no banco
    const { data: recharge, error } = await supabase
      .from("recharges")
      .select("*")
      .eq("id", rechargeId)
      .single();

    if (error || !recharge) {
      throw new Error("Recarga não encontrada");
    }

    // Já confirmada no banco — retorna direto
    if (recharge.gateway_status === "confirmed") {
      return new Response(
        JSON.stringify({ status: "confirmed", newBalance: null }),
        { headers: { "Content-Type": "application/json", ...corsHeaders } },
      );
    }

    // 2. Consultar status direto no Pagar.me
    const chargeRes = await fetch(
      `${PAGARME_URL}/charges/${recharge.gateway_id}`,
      { headers: { "Authorization": pagarmeAuth() } },
    );
    const charge = await chargeRes.json();

    console.log("Pagar.me charge status:", charge.status);

    const isPaid = charge.status === "paid";

    if (!isPaid) {
      return new Response(
        JSON.stringify({ status: recharge.gateway_status }),
        { headers: { "Content-Type": "application/json", ...corsHeaders } },
      );
    }

    // 3. Pagamento confirmado no Pagar.me — processar crédito
    await supabase
      .from("recharges")
      .update({
        gateway_status: "confirmed",
        confirmed_at: new Date().toISOString(),
      })
      .eq("id", rechargeId);

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

    await supabase.from("transactions").insert({
      motoboy_id: recharge.motoboy_id,
      type: "recharge",
      amount: recharge.amount,
      balance_after: newBalance,
      description: `Recarga PIX confirmada — R$${recharge.amount.toFixed(2)}`,
    });

    return new Response(
      JSON.stringify({ status: "confirmed", newBalance }),
      { headers: { "Content-Type": "application/json", ...corsHeaders } },
    );
  } catch (err: any) {
    console.error("check-pix-status error:", err?.message ?? err);
    return new Response(
      JSON.stringify({ error: err?.message ?? "Erro ao verificar pagamento" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
