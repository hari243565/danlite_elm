// ══════════════════════════════════════════════════════════════════════════
// /admin-force-signout — sign a customer out of every device, on their behalf.
//
// ── THIS FUNCTION DELIBERATELY CONTAINS NO SIGN-OUT LOGIC ────────────────
// It calls public.sign_out_all_devices(p_user_id), the SECURITY DEFINER
// function Phase 7 already shipped and proved: it takes the licence lock
// first (matching claim_session's lock order, to avoid deadlock), revokes
// every unrevoked session, clears licences.active_session_id and
// active_device_id, and returns the number of sessions it revoked.
//
// If you are reading this because you want to change what "sign out" means,
// the change belongs in that function, not here. Re-implementing the session
// sweep in TypeScript would give this project two definitions of a security
// operation that must have exactly one, and the second one would drift.
//
// ── THE ONE DIFFERENCE FROM sign-out-devices/ ────────────────────────────
// The customer-facing supabase/functions/sign-out-devices/ passes
// `userData.user.id` — the CALLER's own id, from their own token — so a
// customer can only ever sign out their own devices. That constraint is the
// whole trust model of that endpoint and is not weakened here; this is a
// separate endpoint that passes an ADMIN-SUPPLIED target id instead, and it
// is gated by requireAdmin() rather than by "you can only affect yourself".
// Two different authorisation stories, two different functions, one shared
// RPC. sign-out-devices/ is untouched by this phase.
//
// ── WHY THIS ONE WRITES ITS OWN AUDIT ROW ────────────────────────────────
// sign_out_all_devices() does not write to audit_log, and it should not start
// now: it is called by the customer's own self-service button thousands of
// times more often than by an admin, and Phase 7 is not being modified. The
// audit record belongs to the ADMIN ACTION, not to the underlying operation,
// so it is written here.
//
// ── AN HONEST LIMITATION ─────────────────────────────────────────────────
// The RPC call and the audit insert are two round trips, not one transaction.
// If the process died between them the sign-out would happen unrecorded. That
// is not hidden: the audit insert's success is reported to the caller as
// `audited`, and a failure is logged loudly with the actor's email. Making it
// atomic would require a new SECURITY DEFINER wrapper around Phase 7's RPC,
// which is more surface area than this phase was scoped to add.
//
// ── REASON REQUIRED, ENFORCED HERE ───────────────────────────────────────
// Grant and revoke have their reason requirement enforced inside the database
// function. This action's underlying RPC is Phase 7's and takes no reason
// parameter, so for this one endpoint the check necessarily lives at this
// layer. It is still required rather than optional: an admin reaching into a
// customer's account and terminating their sessions is exactly the kind of
// action that must not be possible without a recorded "why".
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
      return json({ error: "A reason is required to force a sign-out." }, 400);
    }
    if (reason.length > MAX_REASON) {
      return json({ error: `Reason must be ${MAX_REASON} characters or fewer.` }, 400);
    }

    // ── The Phase 7 RPC. Same name, same single argument, same everything
    //    as sign-out-devices/ — only the id differs. ────────────────────────
    const { data, error } = await admin.rpc("sign_out_all_devices", {
      p_user_id: targetUserId,
    });

    if (error) {
      console.error(
        `sign_out_all_devices failed (actor=${identity.email} target=${targetUserId}): ${error.message}`,
      );
      return json({ error: "Could not sign the user out." }, 500);
    }

    const signedOut = typeof data === "number" ? data : 0;

    const { error: auditErr } = await admin.from("audit_log").insert({
      user_id: targetUserId,
      action: "admin.force_signout",
      detail: {
        reason,
        sessions_revoked: signedOut,
      },
      actor_user_id: identity.userId,
      actor_email: identity.email,
    });

    if (auditErr) {
      // Loud, and surfaced to the caller. The sign-out already happened and
      // cannot be undone by failing the request, so returning 500 here would
      // tell the operator the opposite of the truth. Reporting
      // `audited: false` is the honest answer.
      console.error(
        `AUDIT WRITE FAILED for admin.force_signout (actor=${identity.email} target=${targetUserId}): ${auditErr.message}`,
      );
    }

    console.info(
      `admin.force_signout actor=${identity.email} target=${targetUserId} sessions_revoked=${signedOut}`,
    );

    return json(
      { ok: true, sessions_revoked: signedOut, audited: !auditErr },
      200,
    );
  } catch (err) {
    console.error(
      "admin-force-signout error:",
      err instanceof Error ? err.message : String(err),
    );
    return json({ error: "Could not sign the user out." }, 500);
  }
});
