// Shared shell for every /legal/* page.
//
// The DRAFT banner lives here rather than in each page so that every page
// carries an identical warning and none can quietly lose it during an edit.
// It now switches itself off only when lib/legal-config.ts has no unresolved
// placeholder AND APPROVED_FOR_PUBLICATION is true, so filling in the config
// is not by itself enough to "publish" a text nobody has approved.
//
// These pages are public: no session is needed, and they load no third-party
// script. They are also the only indexable pages on the portal (see
// INDEXABLE in ./_components/legal.tsx, app/robots.ts and proxy.ts).

import { DraftBanner, LegalNav, legalStyles as s } from './_components/legal';

export default function LegalLayout({ children }: { children: React.ReactNode }) {
  return (
    <main className={s.page}>
      <DraftBanner />
      {children}
      <LegalNav />
    </main>
  );
}
