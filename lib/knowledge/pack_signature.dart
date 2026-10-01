/// Danlite ELM — knowledge-pack signatures.
///
/// Reuses the project's existing Ed25519 primitive (`package:cryptography`,
/// the one `entitlement_service.dart` verifies licence tokens with). It does
/// NOT reuse the licence key: a pack has its own canonical bytes and its own
/// key pair, so a leak or misuse of one cannot forge the other.
///
/// FAIL CLOSED. A downloaded pack is accepted only with a valid signature
/// under [kKnowledgePackPublicKeyBase64] — and that key is not set, so today
/// every downloaded pack is rejected. The bundled baseline is not checked
/// here: it is trusted because the signed APK carries it.
///
/// Pure Dart.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'kb_models.dart';

/// PRODUCTION KNOWLEDGE-PACK PUBLIC KEY — NOT SET.
///
/// Base64 of the RAW 32-byte Ed25519 public key (the form
/// `SimplePublicKey` takes), once the owner has created the pack-signing key
/// pair. While this is null, `verifyPackSignature` refuses every pack with
/// [PackSignatureCheck.noKeyConfigured]. Never put a placeholder here: any
/// 32 bytes would "work" as a key that nobody holds the private half of — or
/// worse, one somebody does.
const String? kKnowledgePackPublicKeyBase64 = null;

/// Domain separator, so these bytes can never be confused with a licence
/// token or any other signed message.
const String kPackSignatureDomain = 'danlite-kb-pack-v1';

enum PackSignatureCheck {
  valid,
  noKeyConfigured,
  noSignature,
  hashMismatch,
  badSignature,
  malformed,
}

/// The exact bytes a pack signature covers: the domain, then each manifest
/// field on its own line, revoked ids sorted. The entries file is covered
/// through `content_sha256`.
Uint8List canonicalPackBytes(PackManifest m) {
  final revoked = [...m.revoked]..sort();
  final lines = <String>[
    kPackSignatureDomain,
    'pack_id=${m.packId}',
    'scope=${m.scope}',
    'language=${m.language}',
    'version=${m.version}',
    'entries_count=${m.entriesCount}',
    'content_sha256=${m.contentSha256}',
    'created_at=${m.createdAt}',
    'min_app_version=${m.minAppVersion}',
    'review_state=${m.reviewState}',
    'key_id=${m.keyId ?? ''}',
    'revoked=${revoked.join(',')}',
  ];
  return Uint8List.fromList(utf8.encode('${lines.join('\n')}\n'));
}

/// Lower-case hex SHA-256 of [bytes].
Future<String> sha256Hex(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  final b = StringBuffer();
  for (final x in hash.bytes) {
    b.write(x.toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

/// Check that [entriesBytes] are the ones [manifest] describes and that the
/// manifest is signed by [publicKey] (raw 32 bytes). [publicKey] null — the
/// production state today — is always a refusal. Never throws.
Future<PackSignatureCheck> verifyPackSignature(
    PackManifest manifest, List<int> entriesBytes, List<int>? publicKey) async {
  try {
    if (publicKey == null) return PackSignatureCheck.noKeyConfigured;
    if (publicKey.length != 32) return PackSignatureCheck.malformed;
    final sig = manifest.signature;
    if (sig == null || sig.isEmpty) return PackSignatureCheck.noSignature;
    if (await sha256Hex(entriesBytes) != manifest.contentSha256) {
      return PackSignatureCheck.hashMismatch;
    }
    final Uint8List sigBytes;
    try {
      sigBytes = base64Url.decode(base64Url.normalize(sig));
    } on FormatException {
      return PackSignatureCheck.malformed;
    }
    if (sigBytes.length != 64) return PackSignatureCheck.malformed;
    final ok = await Ed25519().verify(
      canonicalPackBytes(manifest),
      signature: Signature(sigBytes,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)),
    );
    return ok ? PackSignatureCheck.valid : PackSignatureCheck.badSignature;
  } catch (_) {
    return PackSignatureCheck.malformed;
  }
}

/// The production key as bytes, or null while it is not set.
List<int>? productionPackPublicKey() {
  final k = kKnowledgePackPublicKeyBase64;
  if (k == null) return null;
  try {
    return base64Decode(k);
  } on FormatException {
    return null;
  }
}
