import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

// Custo estimado: OSRM = zero, Google Routes = custo variável por chamada.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

type LatLng = { lat: number; lng: number };

function parsePoint(raw: string): LatLng {
  const [lat, lng] = raw.split(",").map(Number);
  return { lat, lng };
}

function shouldQueryLiveTraffic(origin: LatLng, destination: LatLng, isUrgent: boolean) {
  if (isUrgent) return true;
  const now = new Date();
  const hour = now.getUTCHours() - 3;
  const weekday = now.getUTCDay();
  const isWeekday = weekday >= 1 && weekday <= 5;
  const isPeakHour = (hour >= 7 && hour < 9) || (hour >= 17 && hour < 19);
  const distanceKm = haversineKm(origin, destination);
  return distanceKm > 8 || (isWeekday && isPeakHour);
}

function haversineKm(a: LatLng, b: LatLng) {
  const toRad = (value: number) => value * Math.PI / 180;
  const r = 6371;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const aa =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.atan2(Math.sqrt(aa), Math.sqrt(1 - aa));
}

async function queryOsrm(baseUrl: string, origin: string, destination: string) {
  const response = await fetch(
    `${baseUrl}/route/v1/driving/${origin};${destination}?geometries=geojson&overview=full`,
  );
  const data = await response.json();
  const route = data?.routes?.[0];
  if (!route) throw new Error("OSRM sem rota");

  return {
    distanceMeters: route.distance,
    durationSeconds: Math.round(route.duration),
    durationInTrafficSeconds: Math.round(route.duration),
    trafficRatio: 1,
    polyline: (route.geometry?.coordinates ?? []).map((point: number[]) => [point[1], point[0]]),
    source: "osrm",
  };
}

function parseDuration(duration: string | undefined) {
  if (!duration) return 0;
  return Math.round(Number(duration.replace("s", "")));
}

async function queryGoogleRoutes(apiKey: string, origin: LatLng, destination: LatLng) {
  const response = await fetch("https://routes.googleapis.com/directions/v2:computeRoutes", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask":
        "routes.distanceMeters,routes.duration,routes.staticDuration,routes.polyline.encodedPolyline,routes.travelAdvisory.tollInfo",
    },
    body: JSON.stringify({
      origin: { location: { latLng: { latitude: origin.lat, longitude: origin.lng } } },
      destination: {
        location: { latLng: { latitude: destination.lat, longitude: destination.lng } },
      },
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_AWARE",
      departureTime: new Date().toISOString(),
    }),
  });
  const data = await response.json();
  const route = data?.routes?.[0];
  if (!route) throw new Error(`Routes API sem rota: ${JSON.stringify(data)}`);

  const durationSeconds = parseDuration(route.duration);
  const staticDuration = parseDuration(route.staticDuration) || durationSeconds;

  return {
    distanceMeters: route.distanceMeters,
    durationSeconds,
    durationInTrafficSeconds: durationSeconds,
    trafficRatio: staticDuration > 0 ? Number((durationSeconds / staticDuration).toFixed(2)) : 1,
    polyline: route.polyline?.encodedPolyline ?? "",
    source: "google",
  };
}

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const startedAt = Date.now();
  try {
    const { origin, destination, isUrgent } = await request.json();
    const osrmBaseUrl = Deno.env.get("OSRM_BASE_URL") ?? "https://router.project-osrm.org";
    const googleMapsKey = Deno.env.get("GOOGLE_MAPS_KEY");

    const originPoint = parsePoint(origin);
    const destinationPoint = parsePoint(destination);
    const mustQueryLiveTraffic = shouldQueryLiveTraffic(originPoint, destinationPoint, Boolean(isUrgent));
    const osrmResult = await queryOsrm(osrmBaseUrl, origin, destination);

    let payload = {
      ...osrmResult,
      computedAt: new Date().toISOString(),
    };

    if (mustQueryLiveTraffic && googleMapsKey) {
      try {
        const googleResult = await queryGoogleRoutes(googleMapsKey, originPoint, destinationPoint);
        payload = {
          ...googleResult,
          computedAt: new Date().toISOString(),
        };
      } catch (error) {
        console.error("routing-decision Google fallback", error);
        payload = {
          ...osrmResult,
          source: "osrm_fallback",
          computedAt: new Date().toISOString(),
        };
      }
    }

    return new Response(JSON.stringify(payload), {
      headers: {
        ...corsHeaders,
        "X-Compute-Time": String(Date.now() - startedAt),
      },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: {
        ...corsHeaders,
        "X-Compute-Time": String(Date.now() - startedAt),
      },
    });
  }
});

/*
curl -i --location 'http://127.0.0.1:54321/functions/v1/routing-decision' \
  --header 'Content-Type: application/json' \
  --data '{"origin":"-23.5505,-46.6333","destination":"-23.5630,-46.6550","isUrgent":true}'
*/
