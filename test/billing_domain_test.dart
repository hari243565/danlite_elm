// ══════════════════════════════════════════════════════════════════════════
// THE APP MUST NEVER SHIP A LOCALHOST BILLING DOMAIN.
//
// account_screen.dart renders the three /legal/* addresses as literal,
// SELECTABLE TEXT rather than as tappable links. That makes the value of
// [kBillingDomain] something the customer READS and types, so a wrong value
// is not a dead link the customer can shrug off — it is three printed
// addresses that resolve to their own handset and can never load.
//
// One of those three is the privacy policy Google Play requires to be
// reachable. `http://localhost:3000` shipped in every build until
// 2026-09-22; this test is what stops it, or anything like it, coming back.
//
// The first test RENDERS THE REAL SCREEN and reads the strings back out of
// the widget tree, rather than re-deriving them from the same constant the
// screen uses — re-deriving would pass just as happily with the placeholder
// restored.
// ══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:danlite_elm/providers/auth_provider.dart';
import 'package:danlite_elm/providers/entitlement_provider.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/screens/account_screen.dart';

Widget _harness() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => EntitlementProvider()),
      ],
      child: const MaterialApp(home: AccountScreen()),
    );

void main() {
  testWidgets('the legal addresses the customer actually reads are on the real host',
      (tester) async {
    // The legal card sits at the bottom of a scrolling column, and Flutter
    // does not build what is off-screen. A tall surface renders the whole
    // page in one pass, which is what lets this read the real widgets rather
    // than scrolling and hoping.
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pump(const Duration(milliseconds: 100));

    final rendered = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data ?? '')
        .where((s) => s.contains('/legal/'))
        .toList();

    expect(rendered, hasLength(3),
        reason: 'the screen should render exactly three /legal/ addresses');

    for (final url in rendered) {
      expect(url, startsWith('https://'),
          reason: '$url must be https — it is printed for a customer to type');
      expect(url, isNot(contains('localhost')),
          reason: '$url points at the customer\'s own device');
      expect(url, isNot(contains('0.0.0.0')));
      expect(url, isNot(contains(':3000')));
    }

    expect(
      rendered..sort(),
      equals(const [
        'https://billing.danlite.in/legal/privacy',
        'https://billing.danlite.in/legal/refund',
        'https://billing.danlite.in/legal/terms',
      ]),
    );
  });

  test('kBillingDomain matches the deployed BILLING_DOMAIN secret exactly', () {
    // The Edge Functions' BILLING_DOMAIN secret and the portal's
    // NEXT_PUBLIC_BILLING_DOMAIN hold this same string. A trailing slash here
    // would produce `...in//legal/privacy`, so the shape is asserted too.
    expect(kBillingDomain, equals('https://billing.danlite.in'));
    expect(kBillingDomain, isNot(endsWith('/')));
  });
}
