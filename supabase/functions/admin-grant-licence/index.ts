// ══════════════════════════════════════════════════════════════════════════
// /admin-grant-licence — give a customer a lifetime licence, on purpose,
// with a name attached to the decision.
//
// This is the first admin endpoint in the project that WRITES. Everything
// unusual about it follows from that.
//
// ── WHERE THE ACTOR COMES FROM ───────────────────────────────────────────
// The acting admin's id and email are taken from `identity`, which
// requireAdmin() derived from a JWT it validated against the auth server.
// They are NEVER read from the request body. This is the single most
// important line of defence in the file: if the actor were caller-supplied,
// then the audit trail — the entire point of this phase — would record
// whatever the caller felt like typing, and "who did this?" would be
// answerable only by whoever wanted to lie about it.
//
// A caller therefore chooses WHO IS AFFECTED (target_user_id, from the body)
// but never WHO IS RESPONSIBLE (from the token). That split is the design.
//
// ── WHY THE BODY CHECKS ARE NOT THE REAL ENFORCEMENT ─────────────────────
// The reason check below is a cheap, friendly 400 so an operator gets a clear
// message instead of a database error. The REAL enforcement is inside
// admin_grant_licence(), which raises if the reason is empty. That
// duplication is deliberate and must stay: this function is not the only
// thing that can reach the RPC, and a rule that only exists in the layer an
// attacker skips is not a rule.
//
// ── POST ONLY ────────────────────────────────────────────────────────────
// Same reasoning as sign-out-devices: an action that changes state must not
// sit behind a GET, which is the shape a link prefetcher or crawler follows.
// ══════════════════════════════════════════════════════════════════════════

import { handlePreflight, json, requireAdmin } from "../_shared/admin_guard.ts";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Long enough for a real explanation, short enough that the audit detail
 *  column cannot be used as free storage. */
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
      return json({ error: "A reason is required to grant a licence." }, 400);
    }
    if (reason.length > MAX_REASON) {
      return json({ error: `Reason must be ${MAX_REASON} characters or fewer.` }, 400);
    }

    const { data, error } = await admin.rpc("admin_grant_licence", {
      p_target_user_id: targetUserId,
      // ── From the verified token. Not from the body. See header. ────────
      p_actor_user_id: identity.userId,
      p_actor_email: identity.email,
      p_reason: reason,
    });

    if (error) {
      // Logged WITH the actor, because a failed privileged action is at least
      // as interesting as a successful one when reading logs after an
      // incident.
      console.error(
        `admin_grant_licence failed (actor=${identity.email} target=${targetUserId}): ${error.message}`,
      );
      return json({ error: "Could not grant the licence." }, 500);
    }

    console.info(
      `admin.licence_granted actor=${identity.email} target=${targetUserId}`,
    );

    return json({ ok: true, result: data }, 200);
  } catch (err) {
    console.error(
      "admin-grant-licence error:",
      err instanceof Error ? err.message : String(err),
    );
    return json({ error: "Could not grant the licence." }, 500);
  }
});
