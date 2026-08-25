// ══════════════════════════════════════════════════════════════════════════
// /sign-out-devices — the escape hatch for a lost or replaced phone.
//
// Revokes every live session for the caller and clears the licence's active
// session, so the next login on ANY device wins cleanly with nothing to
// supersede.
//
// This exists for ONE caller: the explicit "Sign out all devices" button on
// the billing portal's /account page, pressed deliberately by the user after
// a confirmation step. It is never called on a page load, never on a timer,
// and never by the Android app. That distinction is the whole reason the
// portal is safe to visit: loading a page must never disturb a running
// phone, but a user who has lost that phone still needs a way out.
//
// TRUST MODEL: the user id comes from the verified JWT, never from the body.
// A caller can therefore only ever sign out their OWN devices.
// ══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { captureFunctionError } from "../_shared/sentry.ts";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  // A destructive action must not be reachable by a GET — that is the shape a
  // link prefetcher or a naive crawler would follow.
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return json({ error: "missing bearer token" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userErr } = await authClient.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: "invalid or expired token" }, 401);
    }

    const adminClient = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data, error } = await adminClient.rpc("sign_out_all_devices", {
      p_user_id: userData.user.id,
    });

    if (error) {
      console.error("sign_out_all_devices failed:", error.message);
      return json({ error: "sign out failed" }, 500);
    }

    return json({ signed_out: typeof data === "number" ? data : 0 }, 200);
  } catch (err) {
    console.error(
      "sign-out-devices error:",
      err instanceof Error ? err.message : String(err),
    );
    // Report-only (Phase 9): the 500 below is unchanged.
    await captureFunctionError("sign-out-devices", err);
    return json({ error: "sign out failed" }, 500);
  }
});
