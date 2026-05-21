import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

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
    const dashboardToken = Deno.env.get("DASHBOARD_TOKEN");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) throw new Error("Supabase env ausente");

    const response = await fetch(`${supabaseUrl}/functions/v1/generate-report`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${dashboardToken ?? serviceRoleKey}`,
        apikey: serviceRoleKey,
      },
    });
    const payload = await response.json();

    return new Response(JSON.stringify(payload), { headers: corsHeaders });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});

// supabase/config.toml
// [functions.weekly-report-cron]
// verify_jwt = false
// [edge_runtime.cron]
// schedule = "0 8 * * 1"
