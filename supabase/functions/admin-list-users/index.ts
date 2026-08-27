// ══════════════════════════════════════════════════════════════════════════
// /admin-list-users — paginated, searchable customer list.
//
// READ ONLY. No writes of any kind.
//
// ── WHY THIS JOINS BY HAND INSTEAD OF USING A POSTGREST EMBED ────────────
// The obvious implementation is a single query with an embedded resource:
//
//     .select('id, email, ..., licences(status, ...)')
//
// It does not work on this schema, and the reason is worth recording so the
// next person does not try it again. Verified live against
// information_schema: the ONLY foreign key among the public tables is
// sessions.device_id -> devices. Every `user_id` column — on licences,
// payments, orders, devices, sessions — references auth.users(id), in the
// AUTH schema, not public.profiles(id).
//
// PostgREST infers embeds from foreign keys, so there is no
// profiles -> licences relationship for it to follow, and the embed fails
// the whole query rather than degrading. The fix is NOT to add a foreign
// key: that would alter an existing table's schema, which this phase is
// explicitly forbidden to do, and it would rewrite constraints on live
// money-relevant tables to make an internal list page tidier.
//
// So the join happens here, in two batched queries. Same result, no schema
// change, and one round trip more than the embed would have cost.
// ══════════════════════════════════════════════════════════════════════════

import { handlePreflight, json, requireAdmin } from "../_shared/admin_guard.ts";

const DEFAULT_PAGE_SIZE = 25;
const MAX_PAGE_SIZE = 100;

/** Licence statuses this filter will accept. An allowlist, not a passthrough:
 *  the value goes into a PostgREST .eq() and an unbounded string there is a
 *  needless place to be clever. */
const LICENCE_STATUSES = ["active", "inactive", "revoked", "refunded"];

/**
 * Escape a user-supplied search term for PostgREST's `or()` filter syntax.
 *
 * THIS IS NOT COSMETIC. PostgREST parses `or=(a.ilike.x,b.ilike.y)` as a
 * comma-separated list, so an unescaped comma or parenthesis in the search
 * box does not "search for a comma" — it injects an extra filter expression
 * into the query. On a table this function reads with service_role, a
 * caller-controlled filter is not somewhere to find out you were wrong.
 * Percent and underscore are ILIKE wildcards and are neutralised too, so a
 * search for "a_b" means "a_b" and not "a<anything>b".
 */
function sanitizeTerm(raw: string): string {
  return raw
    .trim()
    .slice(0, 120)
    .replace(/[\\%_]/g, (m) => `\\${m}`)
    .replace(/[(),."*]/g, " ")
    .trim();
}

type LicenceRow = {
  user_id: string;
  status: string | null;
  product_code: string | null;
  purchase_rail: string | null;
  purchased_at: string | null;
  revoked_at: string | null;
  revoke_reason: string | null;
};

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

    const rawSearch = typeof body.search === "string" ? body.search : "";
    const search = sanitizeTerm(rawSearch);
    const statusFilter =
      typeof body.status === "string" && LICENCE_STATUSES.includes(body.status)
        ? body.status
        : null;

    const page = Math.max(0, Number(body.page) || 0);
    const pageSize = Math.min(
      MAX_PAGE_SIZE,
      Math.max(1, Number(body.page_size) || DEFAULT_PAGE_SIZE),
    );
    const from = page * pageSize;
    const to = from + pageSize - 1;

    // profiles is the base table, not licences: a user with no licence row
    // must still appear in this list, and starting from licences would
    // silently hide exactly the people an admin most often goes looking for.
    let query = admin
      .from("profiles")
      .select("id, email, first_name, last_name, phone, country_code, signup_platform, created_at, deleted_at", {
        count: "exact",
      });

    if (search) {
      // Name is searchable for the same reason it is now displayed: an
      // operator handling a support email has a person's name in front of
      // them far more often than their account's email address. The same
      // sanitizeTerm() escaping covers these two columns — see its note; the
      // term is still never interpolated raw into a PostgREST filter.
      query = query.or(
        `email.ilike.%${search}%,first_name.ilike.%${search}%,` +
          `last_name.ilike.%${search}%,phone.ilike.%${search}%,` +
          `country_code.ilike.%${search}%`,
      );
    }

    // ── LICENCE-STATUS FILTER ────────────────────────────────────────────
    // Resolved to a set of user ids first, because the status lives on a
    // table PostgREST cannot join to (see the header note).
    //
    // HONEST SCALING NOTE: this pulls every user_id holding the requested
    // status. At the current scale (2 users) that is trivially fine, and it
    // stays fine into the low thousands. If this table ever reaches a size
    // where that is a problem, the right fix is a database view or an RPC
    // that does the join server-side — not a foreign key added to satisfy
    // this page.
    if (statusFilter) {
      const { data: licIds, error: licErr } = await admin
        .from("licences")
        .select("user_id")
        .eq("status", statusFilter);

      if (licErr) {
        console.error("admin-list-users licence filter failed:", licErr.message);
        return json({ error: "Could not load users." }, 500);
      }

      const ids = (licIds ?? []).map((r) => r.user_id).filter(Boolean) as string[];

      if (ids.length === 0) {
        return json(
          {
            users: [],
            page,
            page_size: pageSize,
            total: 0,
            has_more: false,
            applied: { search: search || null, status: statusFilter },
          },
          200,
        );
      }

      query = query.in("id", ids);
    }

    const { data: profiles, count, error } = await query
      .order("created_at", { ascending: false })
      .range(from, to);

    if (error) {
      console.error("admin-list-users query failed:", error.message);
      return json({ error: "Could not load users." }, 500);
    }

    // ── SECOND QUERY: licences for exactly the page just fetched ─────────
    // Batched by id rather than one lookup per row: 25 sequential round
    // trips to render one screen is how an admin list becomes the slowest
    // page in the product.
    const pageIds = (profiles ?? []).map((p) => p.id);
    const licenceByUser: Record<string, LicenceRow> = {};

    if (pageIds.length > 0) {
      const { data: licences, error: licErr } = await admin
        .from("licences")
        .select("user_id, status, product_code, purchase_rail, purchased_at, revoked_at, revoke_reason")
        .in("user_id", pageIds);

      if (licErr) {
        console.error("admin-list-users licence fetch failed:", licErr.message);
        return json({ error: "Could not load users." }, 500);
      }

      for (const l of (licences ?? []) as LicenceRow[]) {
        if (l.user_id) licenceByUser[l.user_id] = l;
      }
    }

    const users = (profiles ?? []).map((u) => {
      const lic = licenceByUser[u.id] ?? null;
      return {
        id: u.id,
        email: u.email,
        first_name: u.first_name,
        last_name: u.last_name,
        phone: u.phone,
        country_code: u.country_code,
        signup_platform: u.signup_platform,
        created_at: u.created_at,
        deleted_at: u.deleted_at,
        licence_status: lic?.status ?? null,
        product_code: lic?.product_code ?? null,
        purchase_rail: lic?.purchase_rail ?? null,
        purchased_at: lic?.purchased_at ?? null,
        revoked_at: lic?.revoked_at ?? null,
        revoke_reason: lic?.revoke_reason ?? null,
      };
    });

    return json(
      {
        users,
        page,
        page_size: pageSize,
        total: count ?? 0,
        has_more: (count ?? 0) > to + 1,
        applied: { search: search || null, status: statusFilter },
      },
      200,
    );
  } catch (err) {
    console.error("admin-list-users error:", err instanceof Error ? err.message : String(err));
    return json({ error: "Could not load users." }, 500);
  }
});
