// ══════════════════════════════════════════════════════════════════════════
// The bridge from this app's Server Components to the admin Edge Functions.
//
// SERVER ONLY. Every function here reads the session cookie, so calling one
// from a Client Component would either fail or, worse, drag the access token
// into the browser bundle.
//
// ── THE SHAPE OF EVERY PAGE LOAD ─────────────────────────────────────────
//   browser  --(httpOnly cookie)-->  this Next.js server
//            --(Bearer access_token)-->  admin-* Edge Function
//            --(service_role)-->  Postgres
//
// The middle hop is the one that matters. This app has no service_role key
// and no direct table access; it can only ask the Edge Functions questions,
// and each of them independently re-checks the caller's email against
// public.admin_users before answering. There is no code path in this app
// that reads a customer row without that check having just happened.
// ══════════════════════════════════════════════════════════════════════════

import { createClient } from '@/lib/supabase/server';

export type AdminSession = {
  accessToken: string;
  email: string;
  userId: string;
};

/**
 * The signed-in admin, or null.
 *
 * getUser() is used for identity — it validates the JWT against the auth
 * server rather than trusting what the cookie claims. getSession() is then
 * used ONLY to lift the raw access_token out for forwarding. That ordering
 * is deliberate: the token is never treated as proof of anything by this
 * app, it is just an opaque credential passed to a function that will
 * validate it again itself.
 */
export async function getAdminSession(): Promise<AdminSession | null> {
  const supabase = await createClient();

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user?.email) return null;

  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session?.access_token) return null;

  return { accessToken: session.access_token, email: user.email, userId: user.id };
}

export type ApiResult<T> =
  | { ok: true; data: T }
  | { ok: false; status: number; error: string };

/**
 * Call an admin Edge Function with the current admin's token.
 *
 * NOTE ON `cache: 'no-store'`: an admin tool must never render a cached
 * answer. Beyond the obvious staleness problem, Next's default fetch caching
 * is keyed on the URL and would happily serve one admin's response to
 * another — and, in a future phase with more than one privilege level, that
 * becomes an authorisation bug rather than a cosmetic one.
 */
export async function callAdminFn<T>(
  fn: string,
  body: Record<string, unknown> = {},
): Promise<ApiResult<T>> {
  const session = await getAdminSession();
  if (!session) return { ok: false, status: 401, error: 'Not signed in.' };

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anon) {
    return { ok: false, status: 500, error: 'Supabase is not configured for this app.' };
  }

  try {
    const res = await fetch(`${url}/functions/v1/${fn}`, {
      method: 'POST',
      cache: 'no-store',
      headers: {
        'Content-Type': 'application/json',
        apikey: anon,
        Authorization: `Bearer ${session.accessToken}`,
      },
      body: JSON.stringify(body),
    });

    const payload = await res.json().catch(() => null);

    if (!res.ok) {
      return {
        ok: false,
        status: res.status,
        error:
          (payload && typeof payload.error === 'string' && payload.error) ||
          `Request failed (HTTP ${res.status}).`,
      };
    }

    return { ok: true, data: payload as T };
  } catch (err) {
    // The message is logged server-side and NOT returned: a fetch failure can
    // carry the internal URL, and this string is rendered on a page.
    console.error(`admin fn ${fn} failed:`, err instanceof Error ? err.message : String(err));
    return { ok: false, status: 502, error: 'Could not reach the admin service.' };
  }
}

// ── Response shapes, mirroring what each Edge Function returns ────────────

export type RecentSignup = {
  id: string;
  email: string | null;
  phone: string | null;
  country_code: string | null;
  signup_platform: string | null;
  created_at: string;
};

export type PaymentRow = {
  id: string;
  user_id: string | null;
  email?: string | null;
  phone?: string | null;
  country_code?: string | null;
  gateway: string | null;
  gateway_order_id: string | null;
  gateway_payment_id: string | null;
  amount_minor: number | null;
  currency: string | null;
  status: string | null;
  gst_invoice_no: string | null;
  created_at: string;
};

export type Overview = {
  generated_at: string;
  razorpay: { isTest: boolean; source: string };
  totals: {
    users: number;
    licences_active: number;
    licences_total: number;
    devices: number;
    captured_payments_count: number;
    captured_minor_inr: number;
    captured_inr: number;
    captured_minor_non_inr: number;
  };
  recent_signups: RecentSignup[];
  recent_payments: PaymentRow[];
};

export type UserRow = {
  id: string;
  email: string | null;
  phone: string | null;
  country_code: string | null;
  signup_platform: string | null;
  created_at: string;
  deleted_at: string | null;
  licence_status: string | null;
  product_code: string | null;
  purchase_rail: string | null;
  purchased_at: string | null;
  revoked_at: string | null;
  revoke_reason: string | null;
};

export type UserList = {
  users: UserRow[];
  page: number;
  page_size: number;
  total: number;
  has_more: boolean;
  applied: { search: string | null; status: string | null };
};

export type UserDetail = {
  profile: {
    id: string;
    email: string | null;
    phone: string | null;
    country_code: string | null;
    signup_platform: string | null;
    deleted_at: string | null;
    created_at: string;
    updated_at: string | null;
  };
  licence: {
    id: string;
    status: string | null;
    product_code: string | null;
    purchase_rail: string | null;
    purchased_at: string | null;
    active_session_id: string | null;
    active_device_id: string | null;
    revoked_at: string | null;
    revoke_reason: string | null;
    created_at: string;
    updated_at: string | null;
  } | null;
  payments: PaymentRow[];
  orders: {
    id: string;
    gateway_order_id: string | null;
    amount_minor: number | null;
    currency: string | null;
    status: string | null;
    created_at: string;
  }[];
  devices: {
    id: string;
    fingerprint: string | null;
    platform: string | null;
    model: string | null;
    last_seen_at: string | null;
    created_at: string;
  }[];
  sessions: {
    id: string;
    device_id: string | null;
    issued_at: string | null;
    last_seen_at: string | null;
    revoked_at: string | null;
    revoke_reason: string | null;
  }[];
  summary: {
    captured_minor: number;
    refunded_minor: number;
    payment_count: number;
    device_count: number;
    active_session_count: number;
  };
};

export type PaymentList = {
  payments: PaymentRow[];
  page: number;
  page_size: number;
  total: number;
  has_more: boolean;
  applied: { search: string | null; status: string | null };
};

export type AuditEntry = {
  id: number;
  user_id: string | null;
  email: string | null;
  action: string;
  detail: unknown;
  ip: string | null;
  created_at: string;
};

export type AuditList = {
  entries: AuditEntry[];
  known_actions: string[];
  page: number;
  page_size: number;
  total: number;
  has_more: boolean;
  applied: { action: string | null; user_id: string | null };
};
