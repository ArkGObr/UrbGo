import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

function encodeGeohash(latitude: number, longitude: number, precision = 6) {
  let idx = 0;
  let bit = 0;
  let evenBit = true;
  let geohash = "";
  let latMin = -90;
  let latMax = 90;
  let lonMin = -180;
  let lonMax = 180;

  while (geohash.length < precision) {
    if (evenBit) {
      const lonMid = (lonMin + lonMax) / 2;
      if (longitude >= lonMid) {
        idx = idx * 2 + 1;
        lonMin = lonMid;
      } else {
        idx *= 2;
        lonMax = lonMid;
      }
    } else {
      const latMid = (latMin + latMax) / 2;
      if (latitude >= latMid) {
        idx = idx * 2 + 1;
        latMin = latMid;
      } else {
        idx *= 2;
        latMax = latMid;
      }
    }

    evenBit = !evenBit;
    if (++bit === 5) {
      geohash += BASE32[idx];
      bit = 0;
      idx = 0;
    }
  }

  return geohash;
}

function isPeakHour(now = new Date()) {
  const brasilHour = Number(
    new Intl.DateTimeFormat("en-US", {
      timeZone: "America/Sao_Paulo",
      hour: "2-digit",
      hour12: false,
    }).format(now),
  );
  return (brasilHour >= 7 && brasilHour < 9) || (brasilHour >= 17 && brasilHour < 19);
}

function buildCacheKey(origin: string, destination: string) {
  const [originLat, originLng] = origin.split(":").map(Number);
  const [destinationLat, destinationLng] = destination.split(":").map(Number);
  return `${encodeGeohash(originLat, originLng, 6)}:${encodeGeohash(destinationLat, destinationLng, 6)}`;
}

export async function getCachedRoute(
  supabaseUrl: string,
  serviceRoleKey: string,
  origin: string,
  destination: string,
) {
  const client = createClient(supabaseUrl, serviceRoleKey);
  const cacheKey = buildCacheKey(origin, destination);
  const { data } = await client
    .from("route_cache")
    .select("id, payload, hit_count")
    .eq("cache_key", cacheKey)
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();

  if (!data) return null;

  await client.from("route_cache").update({ hit_count: (data.hit_count ?? 0) + 1 }).eq("id", data.id);
  return data.payload;
}

export async function setCachedRoute(
  supabaseUrl: string,
  serviceRoleKey: string,
  origin: string,
  destination: string,
  payload: unknown,
) {
  const client = createClient(supabaseUrl, serviceRoleKey);
  const ttlMinutes = isPeakHour() ? 3 : 20;
  const expiresAt = new Date(Date.now() + ttlMinutes * 60_000).toISOString();
  const cacheKey = buildCacheKey(origin, destination);

  if (Math.random() < 0.01) {
    await client.from("route_cache").delete().lt(
      "expires_at",
      new Date(Date.now() - 60 * 60_000).toISOString(),
    );
  }

  await client.from("route_cache").upsert({
    cache_key: cacheKey,
    payload,
    expires_at: expiresAt,
  }, { onConflict: "cache_key" });
}
