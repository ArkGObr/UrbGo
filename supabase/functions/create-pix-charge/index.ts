import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ASAAS_KEY = Deno.env.get("ASAAS_API_KEY")!;
const ASAAS_URL = "https://sandbox.asaas.com/api/v3"; // trocar para prod depois

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
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const { motoboyId, amount } = await req.json();

    if (!motoboyId || !amount || amount < 10) {
      return new Response(
        JSON.stringify({ error: "Valor mínimo de recarga: R$10,00" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // 1. Buscar dados do motoboy
    const userRes = await supabase
      .from("motoboys")
      .select("id, users(name, email, phone)")
      .eq("id", motoboyId)
      .single();

    const user = (userRes.data as any).users;

    // 2. Criar cobrança PIX no Asaas
    const chargeRes = await fetch(`${ASAAS_URL}/payments`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "access_token": ASAAS_KEY,
      },
      body: JSON.stringify({
        customer: motoboyId,
        billingType: "PIX",
        value: amount,
        dueDate: new Date(Date.now() + 30 * 60 * 1000)
          .toISOString()
          .split("T")[0],
        description: `Recarga UrbGo — R$${amount.toFixed(2)}`,
        externalReference: motoboyId,
      }),
    });

    const charge = await chargeRes.json();
    if (!charge.id) throw new Error(JSON.stringify(charge));

    // 3. Buscar QR Code PIX
    const pixRes = await fetch(
      `${ASAAS_URL}/payments/${charge.id}/pixQrCode`,
      {
        headers: { "access_token": ASAAS_KEY },
      }
    );
    const pixData = await pixRes.json();

    // 4. Salvar recarga pendente no banco
    const { data: recharge } = await supabase
      .from("recharges")
      .insert({
        motoboy_id: motoboyId,
        amount: amount,
        gateway_id: charge.id,
        gateway_status: "pending",
        pix_code: pixData.payload,
      })
      .select()
      .single();

    return new Response(
      JSON.stringify({
        rechargeId: recharge.id,
        pixCode: pixData.payload,
        qrCodeBase64: pixData.encodedImage,
        expiresAt: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
      }),
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
      JSON.stringify({ error: "Erro ao gerar cobrança PIX" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
