/// Ed25519 public key for verifying signed entitlement tokens.
/// Safe to expose — a public key can verify signatures but cannot forge them.
/// The matching private key lives ONLY in Supabase Edge Function secrets.
///
/// Encoding: base64 of the RAW 32-byte Ed25519 public key (not SPKI/PEM).
/// That is the form `package:cryptography`'s [SimplePublicKey] expects.
///
/// Rotation note: this key is compiled into the APK. Replacing it requires a
/// new release, so a rotation must ship the new app build BEFORE the Edge
/// Function starts signing with the new private key, or already-installed
/// copies will reject every token they receive.
const String kEntitlementPublicKeyBase64 =
    'ajoKi94K7lTgYpUous4agdQGNfxurcjoxvOeNH/bMhU=';
