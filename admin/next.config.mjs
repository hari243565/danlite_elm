import path from 'node:path';
import { fileURLToPath } from 'node:url';

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
//
// ── WHY THIS FILE IS .mjs AND NOT .ts ────────────────────────────────────
// A next.config.ts has to be compiled before the real build starts, and that
// compilation uses Next's native SWC binary. On Hostinger's Node hosting
// that binary will not load — the system C library there is older than it
// expects:
//
//   Attempted to load @next/swc-linux-x64-gnu ... GLIBC_2.29 not found
//   Failed to load next.config.ts
//
// That is what killed this app's first deployment, before a single line of
// application code was compiled. Plain ESM needs no such pass: Node reads
// this file directly. The type annotation is kept as JSDoc, which gives the
// same editor checking with no compile step.
// ══════════════════════════════════════════════════════════════════════════

// ── WHY `npm run build` PASSES --webpack ──────────────────────────────────
// Same root cause as above, one step further in. Next 16 builds with
// Turbopack by default, and Turbopack is native-only. When its binary will
// not load, Next itself names the remedy — verbatim, from
// node_modules/next/dist/build/swc/index.js:
//
//   "Turbopack is not supported on this platform because native bindings
//    are not available. Only WebAssembly (WASM) bindings were loaded, and
//    Turbopack requires native bindings. Use the --webpack flag instead."
//
// The webpack path runs on those WASM bindings, which Next downloads by
// itself once the native ones fail, so it survives Hostinger's old glibc.
// The flag lives in package.json's "build" script rather than being typed
// into the host's build box, so it applies to every build automatically.
// "dev" deliberately stays on Turbopack — it only runs on a dev machine.
//
// The root pin below still applies under webpack: Next resolves
// `outputFileTracingRoot = outputFileTracingRoot || turbopack.root`
// (next/dist/server/config.js), so dropping it brings the multiple-lockfile
// warning straight back. Verified by A/B on a real webpack build.
// ──────────────────────────────────────────────────────────────────────────

// `import.meta.dirname` (used by the .ts version this replaced) only exists
// from Node 20.11. Next 16 itself allows Node >= 20.9, and the deployment
// target is demonstrably an old environment, so the two-line form below is
// used instead — it resolves to the identical path on every ESM-capable Node.
const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** @type {import('next').NextConfig} */
const nextConfig = {
  turbopack: {
    root: path.resolve(__dirname),
  },
};

export default nextConfig;
