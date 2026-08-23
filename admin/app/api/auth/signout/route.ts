// ══════════════════════════════════════════════════════════════════════════
// POST /api/auth/signout — end the admin's own session.
//
// SCOPE NOTE: this signs out the ADMIN, from the admin tool. It is not the
// "force sign-out a customer" action, which is explicitly out of scope for
// this read-only phase and belongs with the other action buttons in a later
// one. Nothing here touches any customer's session, licence or devices.
//
// signOut() revokes the refresh token server-side and clears the cookies
// through the same @supabase/ssr client that set them, so there is no
// hand-rolled cookie deletion to get subtly wrong.
// ══════════════════════════════════════════════════════════════════════════

import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

export async function POST() {
  try {
    const supabase = await createClient();
    await supabase.auth.signOut();
  } catch (err) {
    // Reported as success regardless. If the token was already invalid, the
    // user's intent — "stop being signed in here" — is satisfied either way,
    // and an error screen would only tempt them to leave the tab open.
    console.error('admin signOut failed:', err instanceof Error ? err.message : String(err));
  }

  return NextResponse.json({ status: 'ok', redirect: '/login' });
}
