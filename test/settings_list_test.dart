import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/settings/settings_list.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Widget listWith({
    required bool enabled,
    Widget? header,
    required VoidCallback onToggle,
  }) {
    return SettingsList(
      enabled: enabled,
      header: header,
      sections: [
        SettingsSection(
          tiles: [
            SettingsTile.switchTile(
              title: const Text('目标开关'),
              initialValue: false,
              onToggle: (_) => onToggle(),
            ),
          ],
        ),
      ],
    );
  }

  testWidgets('enabled list toggles its tiles', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(
      wrap(listWith(enabled: true, onToggle: () => toggled++)),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(toggled, 1);
    final opacity = tester.widget<Opacity>(
      find
          .ancestor(of: find.byType(ListView), matching: find.byType(Opacity))
          .first,
    );
    expect(opacity.opacity, 1);
  });

  testWidgets('disabled list ignores taps and dims its tiles', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(
      wrap(listWith(enabled: false, onToggle: () => toggled++)),
    );

    await tester.tap(find.byType(Switch), warnIfMissed: false);
    await tester.pump();

    expect(toggled, 0);
    final opacity = tester.widget<Opacity>(
      find
          .ancestor(of: find.byType(ListView), matching: find.byType(Opacity))
          .first,
    );
    expect(opacity.opacity, lessThan(1));
  });

  testWidgets('header stays readable while the list is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        listWith(
          enabled: false,
          header: const Text('不可用原因'),
          onToggle: () {},
        ),
      ),
    );

    expect(find.text('不可用原因'), findsOneWidget);
    // The header is rendered outside the dimmed subtree, so its reason is
    // still legible.
    expect(
      find.ancestor(
        of: find.text('不可用原因'),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
  });
}
