// ══════════════════════════════════════════════════════════════════════════
// /admin-list-payments — payment history across every customer.
//
// READ ONLY. Searchable by invoice number, gateway payment/order id, and by
// the payer's email or phone — the last of which is the one an admin
// actually reaches for when a customer emails asking where their licence is.
//
// NO REFUND UI, BY DESIGN. Refunds are issued in Razorpay's own dashboard.
// This function displays refund state that already exists in `payments`
// (written there by razorpay-webhook, which this phase does not touch) and
// offers no way to initiate one.
//
// ── PAYER EMAIL IS JOINED BY HAND ────────────────────────────────────────
// Same schema fact as admin-list-users: payments.user_id references
// auth.users(id), not public.profiles(id), so there is no foreign key for
// PostgREST to follow and a `profiles(email)` embed fails the whole query.
// Verified live against information_schema. The join is done in two batched
// queries below instead. Adding a foreign key to make the embed work would
// mean altering a live money table's schema, which this phase forbids.
// ══════════════════════════════════════════════════════════════════════════

import { handlePreflight, json, requireAdmin } from "../_shared/admin_guard.ts";

const DEFAULT_PAGE_SIZE = 25;
const MAX_PAGE_SIZE = 100;

const PAYMENT_STATUSES = [
  "created",
  "authorized",
  "captured",
  "failed",
  "refunded",
  "partially_refunded",
];

/** See the identical note in admin-list-users: PostgREST's or() filter is
 *  comma-delimited, so an unescaped comma from the search box injects a
 *  filter expression rather than searching for a comma. */
function sanitizeTerm(raw: string): string {
  return raw
    .trim()
    .slice(0, 120)
    .replace(/[\\%_]/g, (m) => `\\${m}`)
    .replace(/[(),."*]/g, " ")
    .trim();
}

const PAYMENT_COLUMNS =
  "id, user_id, gateway, gateway_order_id, gateway_payment_id, amount_minor, currency, status, gst_invoice_no, created_at";

type ProfileLite = { id: string; email: string | null; phone: string | null; country_code: string | null };

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

    const search = sanitizeTerm(typeof body.search === "string" ? body.search : "");
    const statusFilter =
      typeof body.status === "string" && PAYMENT_STATUSES.includes(body.status)
        ? body.status
        : null;

    const page = Math.max(0, Number(body.page) || 0);
    const pageSize = Math.min(
      MAX_PAGE_SIZE,
      Math.max(1, Number(body.page_size) || DEFAULT_PAGE_SIZE),
    );
    const from = page * pageSize;
    const to = from + pageSize - 1;

    // raw_payload is deliberately NOT selected. It is the full gateway
    // response and can carry card metadata and contact details that nothing
    // on this page renders. An admin tool should pull the data it displays,
    // not everything it is permitted to read.
    let query = admin.from("payments").select(PAYMENT_COLUMNS, { count: "exact" });

    if (statusFilter) query = query.eq("status", statusFilter);

    // ── SEARCH ───────────────────────────────────────────────────────────
    // A term can match either a gateway reference ON the payment row, or a
    // person. Both are resolved to a single filter before the page query
    // runs, so paging and the total count stay correct — an earlier version
    // ran a second "fallback" query after the fact and would have reported
    // a total that did not match the rows it returned.
    if (search) {
      const { data: matchedProfiles, error: profErr } = await admin
        .from("profiles")
        .select("id")
        .or(`email.ilike.%${search}%,phone.ilike.%${search}%`)
        .limit(500);

      if (profErr) {
        console.error("admin-list-payments profile search failed:", profErr.message);
        return json({ error: "Could not load payments." }, 500);
      }

      const ids = (matchedProfiles ?? []).map((p) => p.id);

      const refClause =
        `gst_invoice_no.ilike.%${search}%,` +
        `gateway_payment_id.ilike.%${search}%,` +
        `gateway_order_id.ilike.%${search}%`;

      query = query.or(
        ids.length > 0 ? `${refClause},user_id.in.(${ids.join(",")})` : refClause,
      );
    }

    const { data: rows, count, error } = await query
      .order("created_at", { ascending: false })
      .range(from, to);

    if (error) {
      console.error("admin-list-payments query failed:", error.message);
      return json({ error: "Could not load payments." }, 500);
    }

    // ── SECOND QUERY: payer details for exactly the page just fetched ────
    const userIds = [...new Set((rows ?? []).map((p) => p.user_id).filter(Boolean))] as string[];
    const profileById: Record<string, ProfileLite> = {};

    if (userIds.length > 0) {
      const { data: profs, error: pErr } = await admin
        .from("profiles")
        .select("id, email, phone, country_code")
        .in("id", userIds);

      if (pErr) {
        console.error("admin-list-payments payer fetch failed:", pErr.message);
        return json({ error: "Could not load payments." }, 500);
      }

      for (const p of (profs ?? []) as ProfileLite[]) profileById[p.id] = p;
    }

    const payments = (rows ?? []).map((p) => {
      const prof = p.user_id ? profileById[p.user_id] ?? null : null;
      return {
        id: p.id,
        user_id: p.user_id,
        email: prof?.email ?? null,
        phone: prof?.phone ?? null,
        country_code: prof?.country_code ?? null,
        gateway: p.gateway,
        gateway_order_id: p.gateway_order_id,
        gateway_payment_id: p.gateway_payment_id,
        amount_minor: p.amount_minor,
        currency: p.currency,
        status: p.status,
        gst_invoice_no: p.gst_invoice_no,
        created_at: p.created_at,
      };
    });

    return json(
      {
        payments,
        page,
        page_size: pageSize,
        total: count ?? 0,
        has_more: (count ?? 0) > to + 1,
        applied: { search: search || null, status: statusFilter },
      },
      200,
    );
  } catch (err) {
    console.error("admin-list-payments error:", err instanceof Error ? err.message : String(err));
    return json({ error: "Could not load payments." }, 500);
  }
});
