import path from 'node:path';
import type { NextConfig } from 'next';

// ══════════════════════════════════════════════════════════════════════════
// `turbopack.root` is pinned to this directory deliberately.
//
// There are three package-lock.json files in this repository (the Flutter
// project root, portal/, and admin/). Without this line Next.js walks up,
// finds the repo-root lockfile first and infers THAT as the workspace root,
// which it warns about on every build:
//
//   "Next.js inferred your workspace root, but it may not be correct."
//
// Left alone that is not merely noise — the inferred root is what output
// file tracing uses to decide which files to bundle for deployment, so an
// admin build could trace against the wrong tree entirely. Pinning it makes
// this app self-contained and independent of what the billing portal or the
// Flutter project do with their own lockfiles.
// ══════════════════════════════════════════════════════════════════════════

const nextConfig: NextConfig = {
  turbopack: {
    root: path.resolve(import.meta.dirname),
  },
};

export default nextConfig;
