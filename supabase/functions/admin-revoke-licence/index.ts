// ══════════════════════════════════════════════════════════════════════════
// /admin-revoke-licence — take a licence away.
//
// The mirror of admin-grant-licence, and the more dangerous of the two: this
// is the endpoint that can remove access somebody paid for. Read the header
// comment in admin-grant-licence/index.ts — the actor-from-token rule, the
// "body checks are not the real enforcement" rule, and the POST-only rule all
// apply here identically and for the same reasons.
//
// ── WHAT THIS IS *NOT* ───────────────────────────────────────────────────
// It is not a refund. Money is not touched, no gateway is called, and no
// payment row changes. Refunds happen in Razorpay's own dashboard and arrive
// back here through razorpay-webhook, which calls a DIFFERENT function
// (revoke_licence_from_refund) and writes a differently-shaped revoke_reason.
// Keeping the two paths separate is what lets a future reader of
// licences.revoke_reason tell "the gateway refunded them" apart from "a human
// took it away" — see the note in the migration.
// ══════════════════════════════════════════════════════════════════════════

import { handlePreflight, json, requireAdmin } from "../_shared/admin_guard.ts";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const MAX_REASON = 500;

Deno.serve(async (req: Request): Promise<Response> => {
  const pre = handlePreflight(req, ["POST"]);
  if (pre) return pre;

  const guard = await requireAdmin(req);
  if (!guard.ok) return guard.response;
  const { admin, identity } = guard;

  try {
    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;

    const targetUserId =
      typeof body.target_user_id === "string" ? body.target_user_id.trim() : "";
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";

    if (!UUID_RE.test(targetUserId)) {
      return json({ error: "A valid target_user_id is required." }, 400);
    }
    if (reason.length === 0) {
      return json({ error: "A reason is required to revoke a licence." }, 400);
    }
    if (reason.length > MAX_REASON) {
      return json({ error: `Reason must be ${MAX_REASON} characters or fewer.` }, 400);
    }

    const { data, error } = await admin.rpc("admin_revoke_licence", {
      p_target_user_id: targetUserId,
      p_actor_user_id: identity.userId,
      p_actor_email: identity.email,
      p_reason: reason,
    });

    if (error) {
      console.error(
        `admin_revoke_licence failed (actor=${identity.email} target=${targetUserId}): ${error.message}`,
      );
      return json({ error: "Could not revoke the licence." }, 500);
    }

    console.info(
      `admin.licence_revoked actor=${identity.email} target=${targetUserId}`,
    );

    return json({ ok: true, result: data }, 200);
  } catch (err) {
    console.error(
      "admin-revoke-licence error:",
      err instanceof Error ? err.message : String(err),
    );
    return json({ error: "Could not revoke the licence." }, 500);
  }
});
