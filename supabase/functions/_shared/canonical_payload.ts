// ══════════════════════════════════════════════════════════════════════════
// THE CANONICAL SIGNING STRING — READ THIS BEFORE CHANGING ANYTHING HERE
// ══════════════════════════════════════════════════════════════════════════
//
// This file defines the EXACT bytes that get signed. It is the single most
// important detail in the entire entitlement system, because two different
// languages (TypeScript here, Dart in the app) must independently produce
// byte-identical output or every signature check fails.
//
// WE DO NOT SIGN JSON. Signing `JSON.stringify(payload)` is the classic way to
// break this. JSON gives no ordering or formatting guarantees across
// languages: TS emits keys in insertion order, Dart's jsonEncode emits Map
// iteration order, either may differ in whitespace, unicode escaping, or how a
// number is rendered. Any one of those differences changes the bytes and the
// signature no longer verifies — and it fails *intermittently*, only for the
// payloads where the orderings happen to diverge, which is close to
// undebuggable in the field.
//
// Instead: a fixed, positional, pipe-delimited string.
//
//     sub|lic|sid|did|iat|exp
//
// e.g. "a1b2c3d4-...|active||" + "|1755000000|1756209600"
//
// RULES, all load-bearing:
//   • Field ORDER is fixed and must never be reordered.
//   • Every field is present. A null/absent field is the EMPTY STRING, never
//     the text "null" and never omitted. sid/did are empty until Phase 7
//     assigns a session/device, so the common case today is two empty fields
//     and the string contains "||".
//   • Numbers are rendered as plain base-10 integers, no padding, no
//     separators, no exponent. Unix seconds, not milliseconds.
//   • The separator is U+007C "|". No field may itself contain a "|".
//     Enforced by assertNoDelimiter below rather than left to trust: every
//     field is either a UUID, a fixed enum value, or an integer, so a "|"
//     appearing at all means something upstream is wrong and we must fail
//     loudly instead of signing an ambiguous string.
//   • The signed bytes are the UTF-8 encoding of this string.
//
// The Dart side lives in lib/services/entitlement_service.dart and carries a
// copy of this comment. CHANGE ONE, CHANGE BOTH, IN THE SAME COMMIT.
// ══════════════════════════════════════════════════════════════════════════

/** Fields covered by the signature. Mirrors the JSON the function returns. */
export interface EntitlementClaims {
  /** auth user id (uuid) */
  sub: string;
  /** licence status: inactive | active | revoked | refunded */
  lic: string;
  /** active session id, or "" — Phase 7 */
  sid: string;
  /** active device id, or "" — Phase 7 */
  did: string;
  /** issued at, unix seconds */
  iat: number;
  /** expires at, unix seconds */
  exp: number;
}

/** Number of fields in the canonical string. Kept as a named constant so the
 *  Dart side can assert the same shape when it splits a value for debugging. */
export const CANONICAL_FIELD_COUNT = 6;

const DELIMITER = "|";

function assertNoDelimiter(name: string, value: string): void {
  if (value.includes(DELIMITER)) {
    // Signing an ambiguous string would let two different payloads share one
    // signature. Refuse rather than produce a token we cannot reason about.
    throw new Error(
      `canonical payload: field "${name}" contains the "${DELIMITER}" delimiter`,
    );
  }
}

function canonicalInt(name: string, value: number): string {
  if (!Number.isInteger(value)) {
    throw new Error(`canonical payload: field "${name}" must be an integer`);
  }
  // Guard the range where JS integers stop being exact. Unix seconds are
  // nowhere near this, so tripping it means a caller passed milliseconds or
  // garbage.
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`canonical payload: field "${name}" out of range`);
  }
  return String(value);
}

/**
 * Build the exact string that gets signed / verified.
 *
 * Null, undefined and empty are all normalised to the empty string, so a
 * missing sid and an explicitly-null sid produce identical bytes.
 */
export function buildCanonicalPayload(c: EntitlementClaims): string {
  const sub = c.sub ?? "";
  const lic = c.lic ?? "";
  const sid = c.sid ?? "";
  const did = c.did ?? "";

  assertNoDelimiter("sub", sub);
  assertNoDelimiter("lic", lic);
  assertNoDelimiter("sid", sid);
  assertNoDelimiter("did", did);

  return [
    sub,
    lic,
    sid,
    did,
    canonicalInt("iat", c.iat),
    canonicalInt("exp", c.exp),
  ].join(DELIMITER);
}

/** UTF-8 bytes of the canonical string — what actually goes into Ed25519. */
export function canonicalPayloadBytes(c: EntitlementClaims): Uint8Array {
  return new TextEncoder().encode(buildCanonicalPayload(c));
}
