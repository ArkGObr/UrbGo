import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PAGARME_API_KEY = Deno.env.get("PAGARME_API_KEY")!;
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
    const { motoboyId, amount } = await req.json();

    if (!motoboyId || !amount || amount < 10) {
      return new Response(
        JSON.stringify({ error: "Valor mínimo de recarga: R$10,00" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // 1. Buscar dados do motoboy
    const { data: motoboyData, error: motoboyError } = await supabase
      .from("motoboys")
      .select("id, users(name, email)")
      .eq("id", motoboyId)
      .single();

    if (motoboyError || !motoboyData) {
      throw new Error("Motoboy não encontrado");
    }

    const user = (motoboyData as any).users;
    const amountInCents = Math.round(amount * 100);
    const orderCode = `ARKGO-${motoboyId.substring(0, 8)}-${Date.now()}`;

    // 2. Criar order PIX no Pagar.me v5
    const orderRes = await fetch(`${PAGARME_URL}/orders`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": pagarmeAuth(),
      },
      body: JSON.stringify({
        code: orderCode,
        items: [
          {
            amount: amountInCents,
            description: `Recarga ArkGo — R$${amount.toFixed(2)}`,
            quantity: 1,
            code: "recharge",
          },
        ],
        customer: {
          name: user?.name ?? "Entregador ArkGo",
          email: user?.email ?? "entregador@arkgo.app",
          type: "individual",
        },
        payments: [
          {
            payment_method: "pix",
            pix: { expires_in: 1800 }, // 30 minutos
          },
        ],
      }),
    });

    const order = await orderRes.json();

    if (!order.id || !order.charges?.[0]) {
      console.error("Pagar.me error:", JSON.stringify(order));
      throw new Error(`Erro ao criar cobrança: ${order.message ?? "unknown"}`);
    }

    const charge = order.charges[0];
    const transaction = charge.last_transaction;
    const pixCopyPaste: string = transaction?.qr_code ?? "";

    // 3. Buscar imagem do QR Code e converter para base64
    let qrCodeBase64: string | null = null;
    const qrImageUrl: string = transaction?.qr_code_url ?? "";

    if (qrImageUrl) {
      try {
        const qrRes = await fetch(qrImageUrl, {
          headers: { "Authorization": pagarmeAuth() },
        });
        if (qrRes.ok) {
          const buf = await qrRes.arrayBuffer();
          qrCodeBase64 = encodeBase64(new Uint8Array(buf));
        }
      } catch (_) {
        // Fallback: app usará somente o copia-e-cola
      }
    }

    // 4. Salvar recarga pendente no banco
    const { data: recharge, error: insertError } = await supabase
      .from("recharges")
      .insert({
        motoboy_id: motoboyId,
        amount,
        gateway_id: charge.id, // ch_xxx  ← usado no webhook para lookup
        gateway_status: "pending",
        pix_code: pixCopyPaste,
      })
      .select()
      .single();

    if (insertError) throw insertError;

    return new Response(
      JSON.stringify({
        rechargeId: recharge.id,
        pixCode: pixCopyPaste,
        qrCodeBase64,
        expiresAt: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
      }),
      { headers: { "Content-Type": "application/json", ...corsHeaders } },
    );
  } catch (err) {
    console.error("create-pix-charge error:", err);
    return new Response(
      JSON.stringify({ error: "Erro ao gerar cobrança PIX" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
