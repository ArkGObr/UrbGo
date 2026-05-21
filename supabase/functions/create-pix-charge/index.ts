import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

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
    if (!PAGARME_API_KEY) {
      throw new Error("PAGARME_API_KEY não configurado no Supabase Secrets");
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { motoboyId, amount } = await req.json();

    if (!motoboyId || !amount || amount < 10) {
      return new Response(
        JSON.stringify({ error: "Valor mínimo de recarga: R$10,00" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    // 1. Buscar dados do motoboy (incluindo CPF — obrigatório para PIX no Brasil)
    const { data: motoboyData, error: motoboyError } = await supabase
      .from("motoboys")
      .select("id, cpf, users(name, email)")
      .eq("id", motoboyId)
      .single();

    if (motoboyError || !motoboyData) {
      throw new Error("Motoboy não encontrado");
    }

    const motoboy = motoboyData as any;
    const user = motoboy.users;
    const cpf: string = (motoboy.cpf ?? "").replace(/\D/g, "");
    const amountInCents = Math.round(amount * 100);
    const orderCode = `ARKGO-${motoboyId.substring(0, 8)}-${Date.now()}`;

    // 2. Criar order PIX no Pagar.me v5
    const customerPayload: Record<string, any> = {
      name: user?.name ?? "Entregador ArkGo",
      email: user?.email ?? "entregador@arkgo.app",
      type: "individual",
    };

    // CPF é obrigatório para emitir PIX no Brasil
    if (cpf.length === 11) {
      customerPayload.document_type = "CPF";
      customerPayload.document = cpf;
    }

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
        customer: customerPayload,
        payments: [
          {
            payment_method: "pix",
            pix: { expires_in: 1800 },
          },
        ],
      }),
    });

    const order = await orderRes.json();
    console.log("Pagar.me order response:", JSON.stringify(order));

    if (!order.id || !order.charges?.[0]) {
      const detail = order.message ?? order.errors?.[0]?.message ?? JSON.stringify(order);
      throw new Error(`Pagar.me recusou a cobrança: ${detail}`);
    }

    const charge = order.charges[0];
    const transaction = charge.last_transaction;

    console.log("last_transaction:", JSON.stringify(transaction));

    // qr_code pode vir em lugares diferentes dependendo da versão da API
    const pixCopyPaste: string =
      transaction?.qr_code ??
      transaction?.pix?.qr_code ??
      "";

    const qrImageUrl: string =
      transaction?.qr_code_url ??
      transaction?.pix?.qr_code_url ??
      "";

    if (!pixCopyPaste) {
      throw new Error(
        `Pagar.me criou o pedido (${order.id}) mas não retornou o QR code PIX. ` +
        `Status da transação: ${transaction?.status ?? "desconhecido"}. ` +
        `Verifique se o PIX está ativado na sua conta Pagar.me.`,
      );
    }

    // 3. Buscar imagem do QR Code e converter para base64
    let qrCodeBase64: string | null = null;
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
        gateway_id: charge.id,
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
  } catch (err: any) {
    console.error("create-pix-charge error:", err?.message ?? err);
    return new Response(
      JSON.stringify({ error: err?.message ?? "Erro ao gerar cobrança PIX" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
