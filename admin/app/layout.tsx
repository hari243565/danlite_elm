// ══════════════════════════════════════════════════════════════════════════
// Root layout for the admin portal.
//
// The NOINDEX metadata here is search-invisibility layer 2, applied ONCE at
// the root so every current and future page inherits it. Per the installed
// Next.js 16.3.0 Metadata API, a child page's own `metadata` export is merged
// with this one, and a page that does not mention `robots` keeps this value —
// so a page added later is noindex by default rather than by remembering.
// ══════════════════════════════════════════════════════════════════════════

import type { Metadata } from 'next';
import './globals.css';
import { NOINDEX } from '@/lib/seo';

export const metadata: Metadata = {
  title: 'Danlite ELM — Admin',
  description: 'Internal administration tool.',
  robots: NOINDEX,
};

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="en" style={{ height: '100%' }}>
      <body style={{ margin: 0, minHeight: '100%' }}>{children}</body>
    </html>
  );
}
