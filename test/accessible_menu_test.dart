import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/ui/a11y/accessible_menu.dart';

import 'support/localized_app.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Future<void> Function(BuildContext) open,
  ) async {
    SharedPreferences.setMockInitialValues(const {'app_language': 'english'});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: LocalizedTestApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the menu is named by its title', (tester) async {
    final semantics = tester.ensureSemantics();
    String? picked;
    await pump(tester, (context) async {
      picked = await showAccessibleMenu<String>(
        context,
        title: 'Home',
        items: const [
          MenuItemSpec('details', 'Details'),
          MenuItemSpec('remove', 'Remove'),
        ],
      );
    });
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Popup menu'), findsNothing);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(picked, 'remove');
    semantics.dispose();
  });

  testWidgets('a long list scrolls, with the current choice in view', (
    tester,
  ) async {
    int? picked;
    await pump(tester, (context) async {
      picked = await showSingleChoiceMenu<int>(
        context,
        title: 'Country',
        options: {for (var i = 0; i < 60; i++) i: 'Country $i'},
        selected: 45,
      );
    });
    expect(find.text('Country 45 (selected)'), findsOneWidget);
    await tester.tap(find.text('Country 45 (selected)'));
    await tester.pumpAndSettle();
    expect(picked, 45);
  });
}
