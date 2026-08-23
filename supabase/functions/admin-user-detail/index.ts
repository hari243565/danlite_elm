// ══════════════════════════════════════════════════════════════════════════
// /admin-user-detail — everything the system knows about one customer.
//
// READ ONLY, AND DISPLAY ONLY. This phase ships no grant, no revoke, no
// force-sign-out. Those are a deliberately separate later phase, because an
// action button is a different security proposition from a read: a read that
// goes wrong shows the wrong data, a write that goes wrong takes somebody's
// paid licence away. The two should not be built and reviewed in one sitting.
//
// Nothing here writes to audit_log; its schema is untouched this phase.
// ══════════════════════════════════════════════════════════════════════════

import { handlePreflight, json, requireAdmin } from "../_shared/admin_guard.ts";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request): Promise<Response> => {
  const pre = handlePreflight(req, ["GET", "POST"]);
  if (pre) return pre;

  const guard = await requireAdmin(req);
  if (!guard.ok) return guard.response;
  const { admin } = guard;

  try {
    const body =
      req.method === "POST"
        ? await req.json().catch(() => ({} as Record<string, unknown>))
        : Object.fromEntries(new URL(req.url).searchParams);

    const userId = typeof body.user_id === "string" ? body.user_id.trim() : "";

    // Shape-checked before it reaches the database. A malformed uuid would
    // otherwise surface as a Postgres 22P02 error string in the response,
    // which is both an ugly 500 and a small information leak about the
    // backend.
    if (!UUID_RE.test(userId)) {
      return json({ error: "A valid user_id is required." }, 400);
    }

    const [profileRes, licenceRes, paymentsRes, ordersRes, devicesRes, sessionsRes] =
      await Promise.all([
        admin
          .from("profiles")
          .select("id, email, phone, country_code, signup_platform, deleted_at, created_at, updated_at")
          .eq("id", userId)
          .maybeSingle(),
        admin
          .from("licences")
          .select(
            "id, status, product_code, purchase_rail, purchased_at, active_session_id, active_device_id, revoked_at, revoke_reason, created_at, updated_at",
          )
          .eq("user_id", userId)
          .maybeSingle(),
        // raw_payload is deliberately NOT selected. It is the full gateway
        // response and can contain card metadata and contact details that
        // nothing on this page renders. An admin tool should pull the data
        // it displays, not everything it is permitted to read.
        admin
          .from("payments")
          .select(
            "id, gateway, gateway_order_id, gateway_payment_id, amount_minor, currency, status, gst_invoice_no, created_at",
          )
          .eq("user_id", userId)
          .order("created_at", { ascending: false }),
        admin
          .from("orders")
          .select("id, gateway_order_id, amount_minor, currency, status, created_at")
          .eq("user_id", userId)
          .order("created_at", { ascending: false }),
        admin
          .from("devices")
          .select("id, fingerprint, platform, model, last_seen_at, created_at")
          .eq("user_id", userId)
          .order("last_seen_at", { ascending: false }),
        admin
          .from("sessions")
          .select("id, device_id, issued_at, last_seen_at, revoked_at, revoke_reason")
          .eq("user_id", userId)
          .order("issued_at", { ascending: false })
          .limit(50),
      ]);

    if (profileRes.error) {
      console.error("admin-user-detail profile query failed:", profileRes.error.message);
      return json({ error: "Could not load user." }, 500);
    }
    if (!profileRes.data) {
      return json({ error: "No such user." }, 404);
    }

    const firstError = [
      licenceRes.error,
      paymentsRes.error,
      ordersRes.error,
      devicesRes.error,
      sessionsRes.error,
    ].find(Boolean);
    if (firstError) {
      console.error("admin-user-detail query failed:", firstError.message);
      return json({ error: "Could not load user." }, 500);
    }

    const payments = paymentsRes.data ?? [];

    return json(
      {
        profile: profileRes.data,
        licence: licenceRes.data ?? null,
        payments,
        orders: ordersRes.data ?? [],
        devices: devicesRes.data ?? [],
        sessions: sessionsRes.data ?? [],
        // Computed once here so the page never has to add money itself.
        // Refunds already present in payments are reflected by their status,
        // not by any refund action in this tool — refunds stay in Razorpay's
        // own dashboard, and this phase only displays their history.
        summary: {
          captured_minor: payments
            .filter((p) => p.status === "captured")
            .reduce((n, p) => n + (Number(p.amount_minor) || 0), 0),
          refunded_minor: payments
            .filter((p) => p.status === "refunded" || p.status === "partially_refunded")
            .reduce((n, p) => n + (Number(p.amount_minor) || 0), 0),
          payment_count: payments.length,
          device_count: (devicesRes.data ?? []).length,
          active_session_count: (sessionsRes.data ?? []).filter((s) => !s.revoked_at).length,
        },
      },
      200,
    );
  } catch (err) {
    console.error("admin-user-detail error:", err instanceof Error ? err.message : String(err));
    return json({ error: "Could not load user." }, 500);
  }
});
