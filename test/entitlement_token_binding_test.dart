// ══════════════════════════════════════════════════════════════════════════
// SECURITY AUDIT (2026-09-19) — adversarial tests for entitlement token
// SUBJECT BINDING.
//
// ── THE EXPLOIT THESE TESTS PERFORM ──────────────────────────────────────
// An Ed25519 signature proves the SERVER issued a token. It does not prove
// the server issued it to whoever is holding the phone. Before the fix,
// EntitlementService verified the signature and the expiry and then stopped:
// `sub` was parsed, carried around on EntitlementResult, and never once
// compared against the signed-in user.
//
// So a token lifted off a paying account and written into another device's
// secure storage verified perfectly, was unexpired, and came back as
// `offlineGraceActive`. auth_gate.dart ALLOWS on that status regardless of
// the licence string inside the token — deliberately, so a customer who paid
// and then drove into a basement is not locked out. One paid account could
// therefore entitle any number of unpaid signed-in accounts, each for up to
// 14 days, by keeping the network unreachable so the cached path is taken.
//
// This is not a theoretical concern for this product: the shipped APK is
// unobfuscated (minifyEnabled/shrinkResources are false, load-bearing for
// the Bluetooth plugin's native code), so the storage key and blob format
// are plainly readable, and the transplant needs no patched binary at all.
//
// ── HOW THESE TESTS ARE HONEST ───────────────────────────────────────────
// They do not assert on a boolean helper. Every token below is signed with a
// REAL Ed25519 key generated in the test, and every assertion runs the real
// readCached() path — real JSON, real base64url, real signature verification,
// real expiry and clock-rollback logic. The only thing injected is which
// public key to verify against and who is signed in, because the production
// private key lives solely in Supabase Edge Function secrets and must never
// be reachable from here.
//
// Test 3 is the control that makes the rest meaningful: the SAME machinery,
// with the subject matching, must still hand back a usable token. A fix that
// rejected everything would pass tests 1 and 2 and lock out every paying
// customer in the field.
// ══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:danlite_elm/services/entitlement_service.dart';

/// In-memory stand-in for the Android Keystore-backed store. Only the three
/// methods EntitlementService actually calls are overridden.
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage([Map<String, String>? seed])
      : _data = {...?seed},
        super();

  final Map<String, String> _data;

  /// Lets a test assert that a rejected token was actually DESTROYED, not
  /// merely ignored — a token left on disk is one a later code path or a
  /// downgraded build could still pick up.
  Map<String, String> get contents => Map.unmodifiable(_data);

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

/// The exact storage key EntitlementService uses. Hardcoded here on purpose:
/// it is what an attacker reads out of the unobfuscated APK, so the test
/// should name the same literal rather than borrow a private constant.
const String kTokenKey = 'danlite_entitlement_token_v1';

const String kPaidUser = '11111111-1111-4111-8111-111111111111';
const String kFreeUser = '22222222-2222-4222-8222-222222222222';

String _b64Url(List<int> bytes) =>
    base64Encode(bytes).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

void main() {
  late Ed25519 algorithm;
  late SimpleKeyPair serverKeyPair;
  late SimplePublicKey serverPublicKey;

  setUpAll(() async {
    algorithm = Ed25519();
    // Stands in for the Edge Function's ED25519_PRIVATE_KEY. Generated fresh
    // for this run; the production key is not present on this machine and is
    // not needed.
    serverKeyPair = await algorithm.newKeyPair();
    serverPublicKey = await serverKeyPair.extractPublicKey();
  });

  /// Produce a genuinely signed token, exactly as /entitlement would: the
  /// signature covers the canonical positional string `sub|lic|sid|did|iat|exp`
  /// and NOT the JSON. Keep this in step with
  /// supabase/functions/_shared/canonical_payload.ts.
  Future<String> signToken({
    required String sub,
    String lic = 'active',
    String sid = '',
    String did = '',
    int? iat,
    int? exp,
  }) async {
    final issued = iat ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expires = exp ?? issued + 14 * 24 * 60 * 60;
    final canonical = '$sub|$lic|$sid|$did|$issued|$expires';
    final signature = await algorithm.sign(
      utf8.encode(canonical),
      keyPair: serverKeyPair,
    );
    return jsonEncode({
      'sub': sub,
      'lic': lic,
      'sid': sid,
      'did': did,
      'iat': issued,
      'exp': expires,
      'sig': _b64Url(signature.bytes),
      'alg': 'Ed25519',
    });
  }

  EntitlementService serviceFor(
    _FakeSecureStorage storage, {
    required String? signedInAs,
  }) =>
      EntitlementService(
        storage: storage,
        publicKey: serverPublicKey,
        currentUserId: () => signedInAs,
      );

  group('entitlement token subject binding', () {
    test(
      'TEST 1 — a validly-signed token for ANOTHER account is refused and '
      'destroyed (the licence-sharing transplant)',
      () async {
        // The paid account's real, server-signed, unexpired, active token,
        // dropped into an unpaid user's device storage.
        final stolen = await signToken(sub: kPaidUser, lic: 'active');
        final storage = _FakeSecureStorage({kTokenKey: stolen});

        final service = serviceFor(storage, signedInAs: kFreeUser);
        final result = await service.readCached();

        // Before the fix this was offlineGraceActive, which auth_gate.dart
        // turns into GateDecision.allowWithGrace — full paid access.
        expect(
          result.status,
          EntitlementStatus.unknown,
          reason: 'a token naming another account must never be usable; '
              'offlineGraceActive here would be full paid access',
        );
        expect(
          result.status,
          isNot(EntitlementStatus.offlineGraceActive),
          reason: 'this is the exact status the paywall allows on',
        );
        expect(result.isTrustworthy, isFalse);
        expect(result.diagnostic, contains('subject mismatch'));

        // Destroyed, not merely ignored.
        expect(
          storage.contents.containsKey(kTokenKey),
          isFalse,
          reason: 'a token belonging to someone else must be wiped from disk',
        );
      },
    );

    test(
      'TEST 2 — editing `sub` to the attacker\'s own id breaks the signature, '
      'so the transplant cannot be repaired by hand',
      () async {
        // The obvious next move once test 1 blocks the plain transplant:
        // rewrite the subject claim in the JSON to your own user id. `sub` is
        // inside the signed canonical string, so this must fail verification.
        final stolen = await signToken(sub: kPaidUser, lic: 'active');
        final tampered = jsonDecode(stolen) as Map<String, dynamic>;
        tampered['sub'] = kFreeUser;

        final storage = _FakeSecureStorage({kTokenKey: jsonEncode(tampered)});
        final service = serviceFor(storage, signedInAs: kFreeUser);
        final result = await service.readCached();

        expect(result.status, EntitlementStatus.unknown);
        expect(result.isTrustworthy, isFalse);
        expect(
          result.diagnostic,
          'cached token tampered',
          reason: 'must be rejected by the signature check, not the subject '
              'check — proving sub is genuinely covered by the signature',
        );
        expect(storage.contents.containsKey(kTokenKey), isFalse);
      },
    );

    test(
      'TEST 3 — CONTROL: the rightful owner\'s token still works offline',
      () async {
        // The regression this fix must not cause. If this fails, every paying
        // customer in a basement garage is locked out.
        final own = await signToken(sub: kPaidUser, lic: 'active');
        final storage = _FakeSecureStorage({kTokenKey: own});

        final service = serviceFor(storage, signedInAs: kPaidUser);
        final result = await service.readCached(reason: 'offline');

        expect(
          result.status,
          EntitlementStatus.offlineGraceActive,
          reason: 'the rightful owner must still get 14 days of offline grace',
        );
        expect(result.rawLic, 'active');
        expect(result.sub, kPaidUser);
        expect(result.source, EntitlementSource.cache);
        expect(
          storage.contents.containsKey(kTokenKey),
          isTrue,
          reason: 'a valid own token must be kept, not cleared',
        );
      },
    );

    test(
      'TEST 4 — CONTROL: no signed-in user is treated as "cannot tell", not '
      'as theft',
      () async {
        // Deliberate leniency, matching the house rule that a destructive
        // outcome needs an unambiguous signal. A null uid means nobody is
        // signed in, which is not evidence of a transplant — and the gate
        // routes a signed-out user to /login before entitlement is consulted.
        final own = await signToken(sub: kPaidUser, lic: 'active');
        final storage = _FakeSecureStorage({kTokenKey: own});

        final service = serviceFor(storage, signedInAs: null);
        final result = await service.readCached();

        expect(result.status, EntitlementStatus.offlineGraceActive);
        expect(
          storage.contents.containsKey(kTokenKey),
          isTrue,
          reason: 'an unknown current user must not trigger a wipe',
        );
      },
    );

    test(
      'TEST 5 — the subject check does not weaken the expiry check: another '
      'account\'s EXPIRED token is still refused',
      () async {
        // Belt and braces on ordering. Whichever check fires first, the
        // outcome must not be a usable token.
        final past = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60 * 60;
        final stolen = await signToken(
          sub: kPaidUser,
          lic: 'active',
          iat: past - 10,
          exp: past,
        );
        final storage = _FakeSecureStorage({kTokenKey: stolen});

        final service = serviceFor(storage, signedInAs: kFreeUser);
        final result = await service.readCached();

        expect(result.isTrustworthy, isFalse);
        expect(
          result.status,
          isNot(EntitlementStatus.offlineGraceActive),
          reason: 'must not reach the status the paywall allows on',
        );
      },
    );

    test(
      'TEST 6 — a revoked licence belonging to another account is refused '
      'too (refund-then-share)',
      () async {
        // The fraud shape: buy, capture the token, refund, keep sharing. The
        // server marks the licence revoked, but a cached token is signed
        // history and stays verifiable. It must still be refused on a device
        // signed in as somebody else.
        final stolen = await signToken(sub: kPaidUser, lic: 'revoked');
        final storage = _FakeSecureStorage({kTokenKey: stolen});

        final service = serviceFor(storage, signedInAs: kFreeUser);
        final result = await service.readCached();

        expect(result.status, EntitlementStatus.unknown);
        expect(result.diagnostic, contains('subject mismatch'));
        expect(storage.contents.containsKey(kTokenKey), isFalse);
      },
    );
  });
}
