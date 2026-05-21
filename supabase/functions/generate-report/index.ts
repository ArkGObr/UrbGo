import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { PDFDocument, StandardFonts, rgb } from "https://esm.sh/pdf-lib@1.17.1";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const dashboardToken = Deno.env.get("DASHBOARD_TOKEN");
    if (!supabaseUrl || !serviceRoleKey) throw new Error("Supabase env ausente");

    const client = createClient(supabaseUrl, serviceRoleKey);
    const authHeader = request.headers.get("Authorization") ?? "";
    if (dashboardToken && authHeader !== `Bearer ${dashboardToken}` && !authHeader.includes(serviceRoleKey)) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: corsHeaders,
      });
    }

    const metricsResponse = await fetch(
      `${supabaseUrl}/functions/v1/analytics-metrics?period=7d`,
      {
        headers: {
          Authorization: `Bearer ${dashboardToken ?? serviceRoleKey}`,
          apikey: serviceRoleKey,
        },
      },
    );
    const metrics = await metricsResponse.json();

    const pdf = await PDFDocument.create();
    const helvetica = await pdf.embedFont(StandardFonts.Helvetica);
    const addPage = (title: string, lines: string[]) => {
      const page = pdf.addPage([595, 842]);
      page.drawText(title, { x: 40, y: 790, size: 24, font: helvetica, color: rgb(0.1, 0.2, 0.5) });
      let y = 750;
      for (const line of lines) {
        page.drawText(line, { x: 40, y, size: 12, font: helvetica });
        y -= 20;
      }
    };

    addPage("ArkGO - Relatorio de Eficiencia de Roteamento", [
      `Periodo: ultimos 7 dias`,
      `Gerado em: ${new Date().toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })}`,
    ]);
    addPage("Resumo Executivo", [
      `Corridas analisadas: ${metrics.summary?.totalRides ?? 0}`,
      `Minutos economizados: ${metrics.summary?.totalMinutesSaved ?? 0}`,
      `Taxa media de trafego: ${metrics.summary?.avgTrafficRatio ?? 0}`,
      `Precisao da IA: ${metrics.summary?.aiAccuracyPercent ?? 0}%`,
      "A IA reduziu tempo ocioso e elevou previsibilidade operacional no periodo.",
    ]);
    addPage("Analise Detalhada", [
      `Custo total de APIs: R$ ${metrics.costAnalysis?.estimatedApiCostBRL ?? 0}`,
      `Economia media por corrida: R$ ${metrics.costAnalysis?.savingsPerRideBRL ?? 0}`,
      `Top corredores monitorados: ${(metrics.topCorridors ?? []).length}`,
    ]);
    addPage("Metodologia", [
      "As economias sao calculadas comparando ETA base, ETA com IA e duracao real da corrida.",
      "Nenhum dado pessoal de motoboy ou cliente e incluido neste relatorio.",
    ]);

    const pdfBytes = await pdf.save();
    if (pdfBytes.byteLength > 2_000_000) {
      throw new Error("PDF acima de 2MB");
    }

    const now = new Date();
    const year = now.getUTCFullYear();
    const week = getWeekNumber(now);
    const path = `reports/${year}/${week}/relatorio_arkgo_${now.toISOString().slice(0, 10)}.pdf`;
    await client.storage.from("reports").upload(path, pdfBytes, {
      upsert: true,
      contentType: "application/pdf",
    });
    const { data } = await client.storage.from("reports").createSignedUrl(path, 60 * 60 * 24 * 7);

    return new Response(JSON.stringify({
      reportUrl: data?.signedUrl,
      generatedAt: now.toISOString(),
      pageCount: pdf.getPageCount(),
    }), { headers: corsHeaders });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});

function getWeekNumber(date: Date) {
  const first = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const diff = Number(date) - Number(first);
  return Math.ceil((diff / 86400000 + first.getUTCDay() + 1) / 7);
}
