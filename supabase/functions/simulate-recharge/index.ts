// ⚠️ USE APENAS EM DESENVOLVIMENTO — simula recarga sem gateway real
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  try {
    const { motoboyId, amount } = await req.json();

    if (!motoboyId || !amount || amount < 1) {
      return new Response(
        JSON.stringify({ error: "motoboyId e amount são obrigatórios" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // 1. Buscar saldo atual
    const { data: motoboy } = await supabase
      .from("motoboys")
      .select("wallet_balance")
      .eq("id", motoboyId)
      .single();

    const newBalance = (motoboy as any).wallet_balance + amount;

    // 2. Atualizar saldo
    await supabase
      .from("motoboys")
      .update({
        wallet_balance: newBalance,
        updated_at: new Date().toISOString(),
      })
      .eq("id", motoboyId);

    // 3. Registrar transação
    await supabase.from("transactions").insert({
      motoboy_id: motoboyId,
      type: "recharge",
      amount: amount,
      balance_after: newBalance,
      description: "[SIMULADO] Recarga de teste",
    });

    return new Response(
      JSON.stringify({ success: true, newBalance }),
      {
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  } catch (err) {
    console.error(err);
    return new Response(
      JSON.stringify({ error: "Erro ao simular recarga" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
