#!/usr/bin/env node
// ══════════════════════════════════════════════════════════════════════════
// Lists every unresolved {{TODO:…}} placeholder in the legal pages.
//
//   node scripts/check-legal-placeholders.mjs           report, exit 0
//   node scripts/check-legal-placeholders.mjs --strict  exit 1 if any token is
//        unresolved, any token has no OPEN_QUESTIONS mapping, or
//        APPROVED_FOR_PUBLICATION is still false
//
// Run it by hand (from portal/) before publishing. It is deliberately NOT part
// of `npm run build`: a failing build on Hostinger would take the whole
// billing portal down, which is worse than a visibly highlighted placeholder.
//
// No dependencies; plain Node >= 18.
// ══════════════════════════════════════════════════════════════════════════

import { readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const portal = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const strict = process.argv.includes('--strict');
const TOKEN = /\{\{TODO:([A-Z0-9_]+)\}\}/g;

const configPath = path.join(portal, 'lib', 'legal-config.ts');
const legalDir = path.join(portal, 'app', 'legal');

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const p = path.join(dir, name);
    return statSync(p).isDirectory() ? walk(p) : /\.(tsx?|mdx?)$/.test(name) ? [p] : [];
  });
}

const files = [configPath, ...walk(legalDir)];
const config = readFileSync(configPath, 'utf8');

// Token -> OPEN_QUESTIONS id, from the PLACEHOLDER_QUESTIONS block.
const mapBlock = config.slice(config.indexOf('PLACEHOLDER_QUESTIONS'));
const mapping = Object.fromEntries(
  [...mapBlock.matchAll(/^\s*([A-Z0-9_]+):\s*'(Q-\d+)'/gm)].map((m) => [m[1], m[2]]),
);
const approved = /APPROVED_FOR_PUBLICATION\s*=\s*true\b/.test(config);

/** @type {Map<string, string[]>} token -> ["file:line", ...] */
const found = new Map();
for (const f of files) {
  readFileSync(f, 'utf8')
    .split(/\r?\n/)
    .forEach((line, i) => {
      for (const m of line.matchAll(TOKEN)) {
        const where = `${path.relative(portal, f).replaceAll('\\', '/')}:${i + 1}`;
        found.set(m[1], [...(found.get(m[1]) ?? []), where]);
      }
    });
}

const names = [...found.keys()].sort();
const unmapped = names.filter((n) => !mapping[n]);

console.log(`Legal placeholders: ${names.length} unresolved token(s)\n`);
for (const n of names) {
  console.log(`  {{TODO:${n}}}  ${mapping[n] ?? 'NO QUESTION MAPPED'}  ${found.get(n).join(', ')}`);
}
if (unmapped.length) {
  console.log(`\nERROR: ${unmapped.length} token(s) have no entry in PLACEHOLDER_QUESTIONS: ${unmapped.join(', ')}`);
}
console.log(`\nAPPROVED_FOR_PUBLICATION = ${approved}`);

if (strict) {
  const problems = [];
  if (names.length) problems.push(`${names.length} unresolved placeholder(s)`);
  if (unmapped.length) problems.push(`${unmapped.length} unmapped placeholder(s)`);
  if (!approved) problems.push('APPROVED_FOR_PUBLICATION is false');
  if (problems.length) {
    console.log(`\nSTRICT: not ready to publish — ${problems.join('; ')}.`);
    process.exit(1);
  }
  console.log('\nSTRICT: ready to publish.');
}
