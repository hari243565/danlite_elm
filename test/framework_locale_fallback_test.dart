import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:danlite_elm/constants/framework_locale_fallback.dart';
import 'package:danlite_elm/providers/settings_provider.dart';

/// Regression coverage for the "No MaterialLocalizations found" crash that
/// occurred when selecting a language (e.g. Maithili) that Flutter's
/// framework localizations don't ship. Mirrors the exact
/// localizationsDelegates / supportedLocales / localeListResolutionCallback
/// wiring used in lib/app.dart, without pulling in OBD/Bluetooth screens.
Widget _harness(Locale locale) {
  return MaterialApp(
    locale: locale,
    supportedLocales: kFrameworkSupportedLocales,
    localeListResolutionCallback: (locales, supportedLocales) {
      final requested = (locales != null && locales.isNotEmpty) ? locales.first : locale;
      return resolveFrameworkLocale(requested);
    },
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        drawer: const Drawer(child: Center(child: Text('drawer'))),
        body: const Center(child: Text('home')),
      ),
    ),
  );
}

void main() {
  for (final lang in SettingsProvider.supportedLanguages) {
    testWidgets('opening the drawer does not crash for "${lang.code}" (${lang.nameEn})',
        (tester) async {
      await tester.pumpWidget(_harness(Locale(lang.code)));
      await tester.pumpAndSettle();

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('drawer'), findsOneWidget);
    });
  }

  test('resolveFrameworkLocale maps every unsupported code to a supported one', () {
    for (final lang in SettingsProvider.supportedLanguages) {
      final resolved = resolveFrameworkLocale(Locale(lang.code));
      expect(
        kFrameworkSupportedLanguageCodes.contains(resolved.languageCode),
        isTrue,
        reason: '${lang.code} resolved to unsupported "${resolved.languageCode}"',
      );
    }
  });
}
