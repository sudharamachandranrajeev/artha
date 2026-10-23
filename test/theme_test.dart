import 'package:artha/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// The redesign's skins and the theme manager in Settings.
void main() {
  test('every palette builds a complete skin in both brightnesses', () {
    final ids = [for (final p in arthaPalettes) p.id];
    expect(ids.toSet().length, ids.length, reason: 'palette ids must be unique');
    for (final p in arthaPalettes) {
      for (final b in Brightness.values) {
        final t = buildArthaTheme(p, b);
        expect(t.textTheme.bodyLarge?.fontFamily, 'Inter', reason: p.id);
        expect(t.cardTheme.elevation, 0, reason: '${p.id} cards are flat');
        final skin = t.extension<ArthaSkin>();
        expect(skin, isNotNull, reason: p.id);
        expect(skin!.series.length, 4, reason: p.id);
      }
    }
    // The reference palette keeps the sampled paper tones.
    final light = buildArthaTheme(arthaPalettes.first, Brightness.light);
    final dark = buildArthaTheme(arthaPalettes.first, Brightness.dark);
    expect(light.scaffoldBackgroundColor, const Color(0xFFF2F2F2));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF121212));
    expect(light.extension<ArthaSkin>()!.primaryDeep, const Color(0xFF0000C6));
  });

  testWidgets('theme manager switches palette and mode from settings', (tester) async {
    final app = AppHarness(tester)..desktop();
    await app.open(seed: (ledger) => ledger.setUp('GBP'));
    await app.run();
    await app.go('Settings');
    expect(find.text('Appearance'), findsOneWidget);

    await app.tapText('Emerald Classic');
    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.theme!.colorScheme.primary, const Color(0xFF047857));

    await app.tapText('Dark');
    final context = tester.element(find.text('Appearance'));
    expect(Theme.of(context).brightness, Brightness.dark);

    final themeId = await tester.runAsync(() => app.session.db.localSetting('ui.theme'));
    final mode = await tester.runAsync(() => app.session.db.localSetting('ui.mode'));
    expect(themeId, 'emerald');
    expect(mode, 'dark');
    await app.close();
  });
}
