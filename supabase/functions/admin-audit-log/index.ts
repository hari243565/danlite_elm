// ══════════════════════════════════════════════════════════════════════════
// /admin-audit-log — a readable rendering of the existing audit_log table.
//
// READ ONLY, AND EMPHATICALLY SO. audit_log's schema is untouched by this
// phase and nothing here writes to it.
//
// A note on why THIS function, of all of them, writes nothing: it would be
// tempting to log "admin viewed the audit log" into the audit log. That is a
// Phase-2 decision, not a Phase-1 one — an append-only trail that this tool
// can write to is a trail this tool can also flood, and the grant that would
// make it possible (INSERT on audit_log for service_role) is not one to hand
// out as a side effect of building a viewer. Admin reads are visible in the
// Edge Function logs in the meantime.
// ══════════════════════════════════════════════════════════════════════════

import { handlePreflight, json, requireAdmin } from "../_shared/admin_guard.ts";

const DEFAULT_PAGE_SIZE = 50;
const MAX_PAGE_SIZE = 200;

/** See admin-list-users. Same PostgREST or() escaping concern. */
function sanitizeTerm(raw: string): string {
  return raw
    .trim()
    .slice(0, 120)
    .replace(/[\\%_]/g, (m) => `\\${m}`)
    .replace(/[(),."*]/g, " ")
    .trim();
}

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

    const action = sanitizeTerm(typeof body.action === "string" ? body.action : "");
    const userId = typeof body.user_id === "string" ? body.user_id.trim() : "";

    const page = Math.max(0, Number(body.page) || 0);
    const pageSize = Math.min(MAX_PAGE_SIZE, Math.max(1, Number(body.page_size) || DEFAULT_PAGE_SIZE));
    const from = page * pageSize;
    const to = from + pageSize - 1;

    // PHASE 2, and the only change this phase makes to a Phase 1 file. The
    // column list here is explicit rather than `select *`, so audit_log's two
    // new columns would otherwise be invisible in the one tool built to read
    // the audit trail — an audit log that silently omits who performed an
    // action is worse than no viewer at all, because it looks complete.
    let query = admin
      .from("audit_log")
      .select(
        "id, user_id, action, detail, ip, created_at, actor_user_id, actor_email",
        { count: "exact" },
      );

    if (action) query = query.ilike("action", `%${action}%`);
    if (UUID_RE.test(userId)) query = query.eq("user_id", userId);

    const { data, count, error } = await query
      .order("created_at", { ascending: false })
      .order("id", { ascending: false })
      .range(from, to);

    if (error) {
      console.error("admin-audit-log query failed:", error.message);
      return json({ error: "Could not load the audit log." }, 500);
    }

    const rows = data ?? [];

    // audit_log stores only user_id. Resolving those to email addresses in
    // one batched query, rather than letting the page fire one lookup per
    // row, is the difference between a page that opens instantly and one
    // that makes fifty round trips to render a screen of history.
    const ids = [...new Set(rows.map((r) => r.user_id).filter(Boolean))] as string[];
    const emailById: Record<string, string | null> = {};
    if (ids.length > 0) {
      const { data: profs } = await admin
        .from("profiles")
        .select("id, email")
        .in("id", ids);
      for (const p of profs ?? []) emailById[p.id] = p.email;
    }

    // Distinct actions present, so the page can offer a filter built from
    // what the log actually contains rather than a hardcoded list that goes
    // stale the moment a new action is logged by some other function.
    const { data: actionRows } = await admin
      .from("audit_log")
      .select("action")
      .order("created_at", { ascending: false })
      .limit(1000);
    const knownActions = [...new Set((actionRows ?? []).map((r) => r.action))].sort();

    return json(
      {
        entries: rows.map((r) => ({
          id: r.id,
          user_id: r.user_id,
          email: r.user_id ? emailById[r.user_id] ?? null : null,
          action: r.action,
          detail: r.detail,
          ip: r.ip,
          created_at: r.created_at,
          // Null on every system-generated row (webhook, entitlement); set on
          // anything an admin did. actor_email is the historical record and
          // stays readable even if that person later leaves the allowlist.
          actor_user_id: r.actor_user_id,
          actor_email: r.actor_email,
        })),
        known_actions: knownActions,
        page,
        page_size: pageSize,
        total: count ?? 0,
        has_more: (count ?? 0) > to + 1,
        applied: { action: action || null, user_id: UUID_RE.test(userId) ? userId : null },
      },
      200,
    );
  } catch (err) {
    console.error("admin-audit-log error:", err instanceof Error ? err.message : String(err));
    return json({ error: "Could not load the audit log." }, 500);
  }
});
