// ══════════════════════════════════════════════════════════════════════════
// /admin-overview — the numbers on the Overview page.
//
// READ ONLY. This function performs no INSERT, UPDATE or DELETE of any kind,
// and writes nothing to audit_log (whose schema this phase does not touch).
//
// Every field below is computed from the live tables at request time. There
// is no caching layer, deliberately: an admin tool that shows a stale figure
// during an incident is worse than one that takes an extra 200ms.
// ══════════════════════════════════════════════════════════════════════════

import { handlePreflight, json, requireAdmin } from "../_shared/admin_guard.ts";

/**
 * Test-vs-live, derived server-side from the key prefix.
 *
 * ONLY THE BOOLEAN CROSSES THE WIRE. RAZORPAY_KEY_ID itself is never placed
 * in the response — not because the Key ID is especially secret (Razorpay's
 * own Checkout.js receives it in the browser), but because an admin API that
 * will happily echo one environment secret is an admin API that will
 * eventually be extended to echo a worse one.
 *
 * Matches the Phase 5 Mission Control treatment exactly: `rzp_test_` prefix
 * means test. Anything else — including an unset key — is reported as LIVE,
 * because the failure that actually costs money is believing you are in test
 * mode when you are not. Unknown must therefore read as dangerous, not safe.
 */
function razorpayMode(): { isTest: boolean; source: string } {
  const key = Deno.env.get("RAZORPAY_KEY_ID") ?? "";
  if (!key) return { isTest: false, source: "RAZORPAY_KEY_ID not set" };
  return {
    isTest: key.startsWith("rzp_test_"),
    source: "RAZORPAY_KEY_ID prefix, read server-side",
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  const pre = handlePreflight(req, ["GET", "POST"]);
  if (pre) return pre;

  const guard = await requireAdmin(req);
  if (!guard.ok) return guard.response;
  const { admin } = guard;

  try {
    // Counts use head:true — Postgres returns the count without shipping a
    // single row back. On a table that will eventually hold every customer,
    // selecting rows just to call .length on them is how an admin dashboard
    // becomes the slowest page in the product.
    const [
      usersRes,
      activeLicRes,
      totalLicRes,
      capturedRes,
      signupsRes,
      paymentsRes,
      devicesRes,
    ] = await Promise.all([
      admin.from("profiles").select("id", { count: "exact", head: true }).is("deleted_at", null),
      admin.from("licences").select("id", { count: "exact", head: true }).eq("status", "active"),
      admin.from("licences").select("id", { count: "exact", head: true }),
      // Amounts are summed in this function rather than by a SQL aggregate
      // because service_role holds no EXECUTE on a custom aggregate function
      // and this phase adds no RPC. Captured payments are a small set.
      admin.from("payments").select("amount_minor, currency").eq("status", "captured"),
      admin
        .from("profiles")
        .select("id, email, phone, country_code, signup_platform, created_at")
        .is("deleted_at", null)
        .order("created_at", { ascending: false })
        .limit(10),
      admin
        .from("payments")
        .select(
          "id, user_id, gateway, gateway_payment_id, gateway_order_id, amount_minor, currency, status, gst_invoice_no, created_at",
        )
        .order("created_at", { ascending: false })
        .limit(10),
      admin.from("devices").select("id", { count: "exact", head: true }),
    ]);

    const firstError = [
      usersRes.error,
      activeLicRes.error,
      totalLicRes.error,
      capturedRes.error,
      signupsRes.error,
      paymentsRes.error,
      devicesRes.error,
    ].find(Boolean);

    if (firstError) {
      console.error("admin-overview query failed:", firstError.message);
      return json({ error: "Could not load overview data." }, 500);
    }

    // Summed in minor units (paise) and only converted for display. Money is
    // never held as a float here: 109.00 is not representable in binary
    // floating point, and a dashboard that quietly drifts by a paise per row
    // is a dashboard nobody can reconcile against Razorpay.
    let capturedMinorINR = 0;
    let capturedMinorOther = 0;
    for (const p of capturedRes.data ?? []) {
      const amt = Number(p.amount_minor) || 0;
      if ((p.currency ?? "INR") === "INR") capturedMinorINR += amt;
      else capturedMinorOther += amt;
    }

    return json(
      {
        generated_at: new Date().toISOString(),
        razorpay: razorpayMode(),
        totals: {
          users: usersRes.count ?? 0,
          licences_active: activeLicRes.count ?? 0,
          licences_total: totalLicRes.count ?? 0,
          devices: devicesRes.count ?? 0,
          captured_payments_count: (capturedRes.data ?? []).length,
          captured_minor_inr: capturedMinorINR,
          captured_inr: capturedMinorINR / 100,
          // Surfaced separately rather than folded into the INR figure.
          // Adding paise to cents would produce a number that is wrong in a
          // way nobody would notice until Phase 6 turns on other currencies.
          captured_minor_non_inr: capturedMinorOther,
        },
        recent_signups: signupsRes.data ?? [],
        recent_payments: paymentsRes.data ?? [],
      },
      200,
    );
  } catch (err) {
    console.error("admin-overview error:", err instanceof Error ? err.message : String(err));
    return json({ error: "Could not load overview data." }, 500);
  }
});
