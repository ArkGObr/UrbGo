import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
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
    if (!supabaseUrl || !serviceRoleKey) throw new Error("SUPABASE env ausente");

    const authHeader = request.headers.get("Authorization") ?? "";
    if (
      serviceRoleKey &&
      !authHeader.includes(serviceRoleKey) &&
      dashboardToken &&
      authHeader !== `Bearer ${dashboardToken}`
    ) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: corsHeaders,
      });
    }

    const url = new URL(request.url);
    const period = url.searchParams.get("period") ?? "7d";
    const days = period === "90d" ? 90 : period === "30d" ? 30 : 7;
    const client = createClient(supabaseUrl, serviceRoleKey);

    const { data: sessions } = await client
      .from("route_sessions")
      .select("*")
      .gte("created_at", new Date(Date.now() - days * 24 * 60 * 60_000).toISOString())
      .order("created_at", { ascending: true });

    const items = sessions ?? [];
    const totalRides = items.length;
    const totalMinutesSaved = round(
      items.reduce((sum, item) => sum + (item.ai_savings_seconds ?? 0), 0) / 60,
    );
    const avgTrafficRatio = round(
      totalRides > 0
        ? items.reduce((sum, item) => sum + Number(item.traffic_ratio ?? 1), 0) / totalRides
        : 0,
    );
    const totalTollsCollectedBRL = round(
      items.reduce((sum, item) => sum + Number(item.toll_cost_brl ?? 0), 0),
    );
    const aiAccuracyPercent = round(
      totalRides > 0
        ? items.filter((item) =>
          item.gemini_eta_seconds != null &&
          item.actual_duration_seconds != null &&
          Math.abs(item.gemini_eta_seconds - item.actual_duration_seconds) < 120
        ).length / totalRides * 100
        : 0,
    );
    const alerts = items.reduce((sum, item) => sum + Number(item.alerts_count ?? 0), 0);
    const reroutesAccepted = items.reduce((sum, item) => sum + Number(item.reroutes_accepted ?? 0), 0);
    const rerouteAcceptanceRate = round(alerts > 0 ? reroutesAccepted / alerts * 100 : 0);

    const timeSeriesMap = new Map<string, { minutesSaved: number; rides: number; avgRatioTotal: number }>();
    for (const item of items) {
      const date = String(item.created_at).slice(0, 10);
      const current = timeSeriesMap.get(date) ?? { minutesSaved: 0, rides: 0, avgRatioTotal: 0 };
      current.minutesSaved += Number(item.ai_savings_seconds ?? 0) / 60;
      current.rides += 1;
      current.avgRatioTotal += Number(item.traffic_ratio ?? 1);
      timeSeriesMap.set(date, current);
    }

    const timeSeries = [...timeSeriesMap.entries()].map(([date, value]) => ({
      date,
      minutesSaved: round(value.minutesSaved),
      rides: value.rides,
      avgRatio: round(value.avgRatioTotal / value.rides),
    }));

    const topCorridors = items.slice(0, 5).map((item, index) => ({
      origin_area: `Origem ${index + 1}`,
      destination_area: `Destino ${index + 1}`,
      avgDelay: Number(item.gemini_eta_seconds ?? item.osrm_eta_seconds ?? 0) -
        Number(item.osrm_eta_seconds ?? 0),
      count: 1,
    }));

    const totalApiCallsEstimated = totalRides * 2;
    const estimatedApiCostBRL = round(totalApiCallsEstimated * 0.06);
    const costPerRideBRL = round(totalRides > 0 ? estimatedApiCostBRL / totalRides : 0);
    const savingsPerRideBRL = round(totalRides > 0 ? totalMinutesSaved * 1.75 / totalRides : 0);

    const payload = {
      summary: {
        totalRides,
        totalMinutesSaved,
        avgTrafficRatio,
        totalTollsCollectedBRL,
        aiAccuracyPercent,
        rerouteAcceptanceRate,
      },
      timeSeries,
      topCorridors,
      costAnalysis: {
        totalApiCallsEstimated,
        estimatedApiCostBRL,
        costPerRideBRL,
        savingsPerRideBRL,
      },
      liveNow: {
        activeAiRides: items.filter((item) => item.routing_source !== "osrm").length,
      },
      recentEvents: items.slice(-5).reverse().map((item) => ({
        createdAt: item.created_at,
        area: "Zona urbana",
        minutesSaved: round(Number(item.ai_savings_seconds ?? 0) / 60),
        tollCostBrl: Number(item.toll_cost_brl ?? 0),
      })),
      generatedAt: new Date().toISOString(),
    };

    const etag = await crypto.subtle.digest(
      "SHA-1",
      new TextEncoder().encode(JSON.stringify(payload)),
    );
    const etagValue = [...new Uint8Array(etag)].map((v) => v.toString(16).padStart(2, "0")).join("");
    if (request.headers.get("If-None-Match") === etagValue) {
      return new Response(null, { status: 304, headers: { ...corsHeaders, ETag: etagValue } });
    }

    return new Response(JSON.stringify(payload), {
      headers: {
        ...corsHeaders,
        ETag: etagValue,
        "Cache-Control": "max-age=300",
      },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});

function round(value: number) {
  return Number(value.toFixed(2));
}

// Seed rapido:
// insert into public.route_sessions (...) values (...);
