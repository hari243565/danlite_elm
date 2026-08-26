// ══════════════════════════════════════════════════════════════════════════
// / — sends visitors to the main Danlite site.
//
// This route used to render Mission Control, the internal phase dashboard.
// That page is now at /mission-control in the admin app, behind the admin
// allowlist. It was never safe here: proxy.ts protects /checkout,
// /confirmation and /account by prefix, and `/` was on none of those lists,
// so the dashboard was readable by anyone who typed this domain. robots.txt
// and X-Robots-Tag stopped it being indexed, which is a different thing from
// stopping it being read.
//
// This portal has no landing page of its own by design. Customers arrive on
// a deep link — an activation link from an email, or /checkout — and never
// at the root. So the root belongs to the marketing site.
//
// redirect() issues a real 307 from the server. A client-side redirect would
// serve a 200 with an empty body first, which flashes and, more importantly,
// means the route still *has* a body that could later be given content by
// accident. There is nothing to render here.
// ══════════════════════════════════════════════════════════════════════════

import { redirect } from 'next/navigation';

export const dynamic = 'force-dynamic';

export default function RootPage() {
  redirect('https://danlite.in');
}
