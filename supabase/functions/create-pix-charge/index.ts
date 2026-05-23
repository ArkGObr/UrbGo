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

/** Formata telefone brasileiro para o formato exigido pelo Pagar.me */
function parsePhone(raw: string): { country_code: string; area_code: string; number: string } | null {
  const digits = raw.replace(/\D/g, "");
  // Remove DDI 55 se presente
  const local = digits.startsWith("55") && digits.length >= 12
    ? digits.slice(2)
    : digits;
  if (local.length < 10) return null;
  return {
    country_code: "55",
    area_code: local.slice(0, 2),
    number: local.slice(2),
  };
}

/** Extrai qr_code e qr_code_url de uma transação Pagar.me (aceita vários formatos) */
function extractPixData(transaction: any): { qrCode: string; qrUrl: string } {
  if (!transaction) return { qrCode: "", qrUrl: "" };
  const qrCode: string =
    transaction.qr_code ??
    transaction.pix?.qr_code ??
    transaction.pix_data?.qr_code ??
    "";
  const qrUrl: string =
    transaction.qr_code_url ??
    transaction.pix?.qr_code_url ??
    transaction.pix_data?.qr_code_url ??
    "";
  return { qrCode, qrUrl };
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

    // 1. Buscar dados do motoboy (CPF e telefone obrigatórios para PIX)
    const { data: motoboyData, error: motoboyError } = await supabase
      .from("motoboys")
      .select("id, cpf, users(name, email, phone)")
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

    // CPF é obrigatório para emitir PIX no Brasil
    if (cpf.length !== 11) {
      throw new Error(
        "Seu CPF não está cadastrado no perfil. " +
          "Entre em contato com o suporte para atualizar seu cadastro.",
      );
    }

    // 2. Criar order PIX no Pagar.me v5
    const phone = parsePhone(user?.phone ?? "");
    const customerPayload: Record<string, any> = {
      name: user?.name ?? "Entregador ArkGo",
      email: user?.email ?? "entregador@arkgo.app",
      type: "individual",
      document_type: "CPF",
      document: cpf,
      phones: {
        mobile_phone: phone ?? {
          country_code: "55",
          area_code: "11",
          number: "999999999",
        },
      },
    };

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
      const detail =
        order.message ?? order.errors?.[0]?.message ?? JSON.stringify(order);
      throw new Error(`Pagar.me recusou a cobrança: ${detail}`);
    }

    const charge = order.charges[0];
    console.log("charge:", JSON.stringify(charge));
    console.log("last_transaction:", JSON.stringify(charge.last_transaction));

    // 3. Tentar extrair QR code do last_transaction ou transactions[]
    let pixCopyPaste = "";
    let qrImageUrl = "";

    const fromLast = extractPixData(charge.last_transaction);
    if (fromLast.qrCode) {
      pixCopyPaste = fromLast.qrCode;
      qrImageUrl = fromLast.qrUrl;
    } else if (charge.transactions?.length > 0) {
      // Tentar em cada transação da lista
      for (const tx of charge.transactions) {
        const fromTx = extractPixData(tx);
        if (fromTx.qrCode) {
          pixCopyPaste = fromTx.qrCode;
          qrImageUrl = fromTx.qrUrl;
          break;
        }
      }
    }

    // 4. Se ainda não temos QR code, buscar a charge diretamente (Pagar.me pode
    //    demorar alguns ms para popular last_transaction no response do order)
    if (!pixCopyPaste && charge.id) {
      console.log("last_transaction vazio — buscando charge diretamente:", charge.id);
      await new Promise((r) => setTimeout(r, 1500)); // aguarda 1.5s
      const chargeRes = await fetch(`${PAGARME_URL}/charges/${charge.id}`, {
        headers: { "Authorization": pagarmeAuth() },
      });
      const chargeDetail = await chargeRes.json();
      console.log("charge detail:", JSON.stringify(chargeDetail));

      const fromDetail = extractPixData(chargeDetail.last_transaction);
      if (fromDetail.qrCode) {
        pixCopyPaste = fromDetail.qrCode;
        qrImageUrl = fromDetail.qrUrl;
      } else if (chargeDetail.transactions?.length > 0) {
        for (const tx of chargeDetail.transactions) {
          const fromTx = extractPixData(tx);
          if (fromTx.qrCode) {
            pixCopyPaste = fromTx.qrCode;
            qrImageUrl = fromTx.qrUrl;
            break;
          }
        }
      }
    }

    if (!pixCopyPaste) {
      const txStatus = charge.last_transaction?.status ?? "desconhecido";
      throw new Error(
        `Pagar.me criou o pedido (${order.id}) mas não retornou o QR code PIX. ` +
          `Status da transação: ${txStatus}. ` +
          `Charge: ${charge.id}. ` +
          `Verifique se o PIX está ativado e se a chave CNPJ está registrada na conta Pagar.me.`,
      );
    }

    // 5. Buscar imagem do QR Code e converter para base64
    let qrCodeBase64: string | null = null;
    if (qrImageUrl) {
      try {
        const qrRes = await fetch(qrImageUrl, {
          headers: { "Authorization": pagarmeAuth() },
        });
        if (qrRes.ok) {
          const buf = await qrRes.arrayBuffer();
          qrCodeBase64 = encodeBase64(new Uint8Array(buf));
        } else {
          console.log("QR image fetch failed, status:", qrRes.status);
        }
      } catch (_) {
        // Fallback: app usa somente o copia-e-cola
      }
    }

    // 6. Salvar recarga pendente no banco
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
