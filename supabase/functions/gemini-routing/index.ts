import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getCachedRoute, setCachedRoute } from "../_shared/route_cache.ts";
import type { GeminiRoutingResponse } from "./types.ts";

/*
Request:
{ "origin":"-23.5505:-46.6333", "destination":"-23.5630:-46.6550", "avoidCurrentCorridor":true }
Response:
{ "optimizedRoute": {...}, "alerts":[...], "trafficRatio":1.21, "tollCost": {...} }
*/

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startedAt = Date.now();

  try {
    const { origin, destination } = await request.json();
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const googleMapsKey = Deno.env.get("GOOGLE_MAPS_KEY");
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");

    if (!supabaseUrl || !serviceRoleKey || !googleMapsKey || !geminiApiKey) {
      throw new Error("Ambiente incompleto para gemini-routing");
    }

    const cached = await getCachedRoute(supabaseUrl, serviceRoleKey, origin, destination);
    if (cached) {
      return new Response(JSON.stringify(cached), {
        headers: {
          ...corsHeaders,
          "X-Cache": "HIT",
          "X-Compute-Time": String(Date.now() - startedAt),
        },
      });
    }

    const [originLat, originLng] = origin.split(":").map(Number);
    const [destinationLat, destinationLng] = destination.split(":").map(Number);
    const routesResponse = await fetch("https://routes.googleapis.com/directions/v2:computeRoutes", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": googleMapsKey,
        "X-Goog-FieldMask":
          "routes.distanceMeters,routes.duration,routes.staticDuration,routes.polyline.encodedPolyline,routes.routeLabels,routes.travelAdvisory",
      },
      body: JSON.stringify({
        origin: { location: { latLng: { latitude: originLat, longitude: originLng } } },
        destination: {
          location: { latLng: { latitude: destinationLat, longitude: destinationLng } },
        },
        travelMode: "DRIVE",
        routingPreference: "TRAFFIC_AWARE",
        departureTime: new Date().toISOString(),
      }),
    });
    const routesData = await routesResponse.json();
    const route = routesData?.routes?.[0];
    if (!route) throw new Error(`Routes sem dados: ${JSON.stringify(routesData)}`);

    const prompt = `
Analise a rota de ${origin} ate ${destination} partindo agora.
Calcule trafego, incidentes e pedagios. Retorne APENAS JSON valido com:
optimizedRoute, eta, trafficRatio, alerts, tollCost.
`;

    const geminiResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${geminiApiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          generationConfig: { responseMimeType: "application/json" },
        }),
      },
    );
    const geminiData = await geminiResponse.json();
    const rawText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;

    let payload: GeminiRoutingResponse;
    if (rawText) {
      payload = JSON.parse(rawText);
    } else {
      const durationSeconds = Number(String(route.duration ?? "0s").replace("s", ""));
      const staticDuration = Number(String(route.staticDuration ?? route.duration ?? "0s").replace("s", ""));
      payload = {
        optimizedRoute: {
          polyline: route.polyline?.encodedPolyline ?? "",
          distanceMeters: route.distanceMeters ?? 0,
          durationSeconds,
          durationInTrafficSeconds: durationSeconds,
        },
        eta: new Date(Date.now() + durationSeconds * 1000).toLocaleTimeString("pt-BR", {
          hour: "2-digit",
          minute: "2-digit",
          timeZone: "America/Sao_Paulo",
        }),
        trafficRatio: staticDuration > 0 ? Number((durationSeconds / staticDuration).toFixed(2)) : 1,
        alerts: [],
        tollCost: { totalBRL: 0, breakdown: [] },
      };
    }

    await setCachedRoute(supabaseUrl, serviceRoleKey, origin, destination, payload);

    return new Response(JSON.stringify(payload), {
      headers: {
        ...corsHeaders,
        "X-Cache": "MISS",
        "X-Compute-Time": String(Date.now() - startedAt),
      },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: {
        ...corsHeaders,
        "X-Cache": "MISS",
        "X-Compute-Time": String(Date.now() - startedAt),
      },
    });
  }
});
