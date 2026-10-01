/// Danlite ELM — the answer to one silent "which codes are stored now?" read,
/// used only for the internal Clear Codes record (fault Phase 1B, B9).
///
/// Pure Dart.
library;

sealed class StoredCodesCheck {
  const StoredCodesCheck(this.at);
  final DateTime at;
}

/// The engine computer answered and listed these stored codes.
final class StoredCodesPresent extends StoredCodesCheck {
  const StoredCodesPresent(this.codes, DateTime at) : super(at);
  final List<String> codes;
}

/// The engine computer answered with an empty stored-code list.
final class StoredCodesEmpty extends StoredCodesCheck {
  const StoredCodesEmpty(DateTime at) : super(at);
}

/// No usable answer: [reason] says why (no answer, refused, busy, link lost,
/// K-line, another operation needed the link, not connected).
final class StoredCodesUnknown extends StoredCodesCheck {
  const StoredCodesUnknown(this.reason, DateTime at) : super(at);
  final String reason;
}
