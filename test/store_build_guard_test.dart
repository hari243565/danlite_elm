/// Build-time guard: a store build must never use the Torque-Pro-derived
/// engine text.
///
/// Runs in the normal suite (where it checks the rule and that the constant
/// follows it) AND is meant to be run as the store build itself:
///
///   flutter test test/store_build_guard_test.dart --dart-define=STORE_BUILD=true
///
/// in which case `kStoreBuild` is true and the constant must be false.
library;

import 'package:danlite_elm/constants/build_flags.dart';
import 'package:danlite_elm/services/dtc_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kUseLegacyEngineText follows the store-build rule', () {
    expect(kUseLegacyEngineText, legacyEngineTextAllowed(storeBuild: kStoreBuild));
    if (kStoreBuild) {
      expect(kUseLegacyEngineText, isFalse,
          reason: 'STORE_BUILD=true must switch the legacy text off');
    }
  });

  test('with STORE_BUILD the resolver returns no legacy text', () {
    if (!kStoreBuild) return; // exercised by the --dart-define run
    // Even if the asset were somehow loaded, nothing reads it.
    DtcLocalizations.loadJsonForTesting(
        '{"en":{"P0198":"legacy en"},"hi":{"P0198":"legacy hi"}}');
    expect(DtcLocalizations.description('P0198', 'en', englishFallback: ''),
        isEmpty);
    expect(DtcLocalizations.description('P0198', 'hi', englishFallback: ''),
        isEmpty);
  });
}
