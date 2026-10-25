import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:artha/app/app.dart';
import 'package:artha/app/providers.dart';
import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// Renders the main pages with the real fonts to PNG files, for checking
/// the look and for the README. Runs only when ARTHA_SHOTS names an output
/// folder: `ARTHA_SHOTS=/tmp/shots flutter test test/screenshots_test.dart`.
///
/// The data is made up: six months of a fictional household's money, dated
/// back from today so the dashboard, forecast and bills look current.
void main() {
  final out = Platform.environment['ARTHA_SHOTS'];

  Future<void> loadFonts() async {
    Future<void> family(String name, List<String> files) async {
      final loader = FontLoader(name);
      for (final f in files) {
        loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
      }
      await loader.load();
    }

    await family('Inter', [
      for (final w in [400, 500, 600, 700, 800]) 'assets/fonts/Inter-$w.ttf',
    ]);
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
    final material = '$flutterRoot/bin/cache/artifacts/material_fonts';
    final icons = File('$material/MaterialIcons-Regular.otf');
    if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
    // Like the desktop, take glyphs Inter lacks (arrows) from the system's
    // sans font, when fontconfig can name one.
    try {
      // The test runner points fontconfig at its own config; ask the system's.
      final r = Process.runSync(
        'fc-match',
        ['-f', '%{file}', 'sans-serif:charset=2192'],
        environment: {'PATH': Platform.environment['PATH'] ?? '', 'HOME': Platform.environment['HOME'] ?? ''},
        includeParentEnvironment: false,
      );
      final file = (r.stdout as String).trim();
      if (r.exitCode == 0 && file.endsWith('.ttf') && File(file).existsSync()) {
        await family('SystemSans', [file]);
      }
    } on ProcessException {
      // No fontconfig: arrows draw as boxes.
    }
  }

  testWidgets('screenshots', skip: out == null, (tester) async {
    await tester.runAsync(loadFonts);
    // Tests draw elevation as black outlines unless told otherwise.
    debugDisableShadows = false;
    final key = GlobalKey();

    Future<void> shot(String name) async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
        return image.toByteData(format: ui.ImageByteFormat.png);
      });
      File('$out/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    Future<AppHarness> start() async {
      final app = AppHarness(tester);
      await app.open(seed: seedHousehold);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ProviderScope(
            overrides: arthaOverrides(app.session),
            retry: (_, _) => null,
            child: const ArthaApp(
              home: _InterEverywhere(child: LinkHandler(child: ArthaHome())),
            ),
          ),
        ),
      );
      await app.settle();
      return app;
    }

    // Phone pages: the bar holds the first few, the rest sit under More.
    Future<void> phoneGo(AppHarness app, String label) async {
      final bar = find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
      if (bar.evaluate().isNotEmpty) {
        await app.tap(bar);
        return;
      }
      await app.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('More')));
      await app.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(label)));
    }

    for (final dark in [false, true]) {
      tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      final app = await start();
      final mode = dark ? 'dark' : 'light';
      await shot('dashboard-$mode');
      for (final page in ['Accounts', 'Transactions', 'Portfolio', 'Insights', 'Reports']) {
        if (dark && page != 'Transactions' && page != 'Portfolio') continue;
        await phoneGo(app, page);
        await shot('${page.toLowerCase()}-$mode');
      }
      await app.close();
    }
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    tester.view.reset();

    tester.view.physicalSize = const Size(1440, 810);
    tester.view.devicePixelRatio = 1;
    final app = await start();
    await shot('dashboard-desktop');
    await app.go('Transactions');
    await shot('transactions-desktop');
    await app.go('Portfolio');
    await shot('portfolio-desktop');
    await app.close();
    tester.view.reset();
    debugDisableShadows = true;
  });
}

/// A made-up household: current account, savings, a cash ISA, a stocks and
/// shares ISA with two funds, a pension and a credit card.
Future<void> seedHousehold(Ledger ledger) async {
  await ledger.setUp('GBP');
  // The page explanations have been read and closed.
  await ledger.db.setLocalSetting(
    'ui.hints.dismissed',
    jsonEncode([
      for (final p in ['dashboard', 'accounts', 'transactions', 'portfolio', 'insights', 'risk', 'recurring'])
        'page.$p',
      for (final p in ['budgets', 'import', 'reports']) 'page.$p',
    ]),
  );
  final now = today();
  final bank = await ledger.saveAccount(
    name: 'Everyday Current',
    subtype: 'current',
    commodityId: 'GBP',
    institution: 'Example Bank',
  );
  final saver = await ledger.saveAccount(
    name: 'Rainy Day Saver',
    subtype: 'savings',
    commodityId: 'GBP',
    institution: 'Example Bank',
  );
  final cashIsa = await ledger.saveAccount(name: 'Cash ISA', subtype: 'isa_cash', commodityId: 'GBP');
  final isa = await ledger.saveAccount(
    name: 'Stocks & Shares ISA',
    subtype: 'isa_stocks',
    commodityId: 'GBP',
  );
  final pension = await ledger.saveAccount(
    name: 'Workplace Pension',
    subtype: 'pension',
    commodityId: 'GBP',
    meta: const {'assetClass': 'equity'},
  );
  final card = await ledger.saveAccount(name: 'Rewards Card', subtype: 'credit_card', commodityId: 'GBP');

  final world = await ledger.createSecurity(
    code: 'GLOBAL',
    name: 'Global All-Cap Index',
    quoteCurrency: 'GBP',
    assetClass: 'equity',
  );
  final gilts = await ledger.createSecurity(
    code: 'GILTS',
    name: 'UK Gilt Index',
    quoteCurrency: 'GBP',
    assetClass: 'bond',
  );
  final worldHolding = await ledger.saveAccount(
    name: 'Global All-Cap Index',
    subtype: 'security',
    commodityId: world,
    parentId: isa,
  );
  final giltHolding = await ledger.saveAccount(
    name: 'UK Gilt Index',
    subtype: 'security',
    commodityId: gilts,
    parentId: isa,
  );

  final start = monthStart(addMonths(now, -6));
  Future<void> opening(String account, int amount) => ledger.saveEntry(
    EntryInput(
      date: start,
      currency: 'GBP',
      payee: 'Opening balance',
      postings: [PostingInput.cash(account, amount), PostingInput.cash(openingBalancesId, -amount)],
    ),
  );
  await opening(bank, 245000);
  await opening(saver, 820000);
  await opening(cashIsa, 1150000);
  await opening(isa, 1600000);
  await opening(pension, 3840000);
  await opening(card, -32000);

  await ledger.saveEntry(
    buyEntry(
      date: addDays(start, 2),
      currency: 'GBP',
      cashAccountId: isa,
      holdingAccountId: worldHolding,
      units: 90000000,
      cost: 1080000,
    ),
  );
  await ledger.saveEntry(
    buyEntry(
      date: addDays(start, 2),
      currency: 'GBP',
      cashAccountId: isa,
      holdingAccountId: giltHolding,
      units: 40000000,
      cost: 400000,
    ),
  );
  for (var m = 0; m <= 6; m++) {
    final d = addDays(start, 30 * m + 1);
    if (d.compareTo(now) > 0) break;
    await ledger.savePrice(
      world,
      'GBP',
      d,
      Rate.parse((120 + 2.1 * m - (m == 3 ? 4 : 0)).toStringAsFixed(2)),
    );
    await ledger.savePrice(gilts, 'GBP', d, Rate.parse((100 + 0.4 * m).toStringAsFixed(2)));
  }

  Future<void> spend(String date, String cat, int amount, String payee, {String? from}) async {
    if (date.compareTo(now) > 0) return;
    await ledger.saveEntry(
      simpleEntry(
        date: date,
        currency: 'GBP',
        accountId: from ?? bank,
        categoryId: cat,
        amount: amount,
        payee: payee,
      ),
    );
  }

  const groceries = ['Fresh Market', 'Corner Grocer', 'Green Basket'];
  const eating = ['Harbour Café', 'Noodle House', 'The Olive Tree'];
  for (var m = 6; m >= 0; m--) {
    final month = monthStart(addMonths(now, -m));
    String day(int d) => addDays(month, d - 1);
    await spend(day(1), 'cat.salary', -342000, 'Acme Studios Ltd');
    await spend(day(2), 'cat.housing', 125000, 'Willow Lettings');
    await spend(day(5), 'cat.council_tax', 16500, 'City Council');
    await spend(day(7), 'cat.utilities', 8400 + m * 230, 'Bright Energy');
    await spend(day(9), 'cat.phone', 2500, 'Example Mobile');
    await spend(day(12), 'cat.subscriptions', 1099, 'StreamFlix');
    await spend(day(15), 'cat.subscriptions', 1199, 'MusicBox');
    await spend(day(18), 'cat.insurance', 2350, 'Safe Home Insurance');
    await spend(day(21), 'cat.transport', 7800, 'Metro Travelcard');
    for (var w = 0; w < 4; w++) {
      await spend(
        day(3 + w * 7),
        'cat.groceries',
        5200 + ((m * 7 + w * 13) % 9) * 410,
        groceries[(m + w) % 3],
      );
    }
    await spend(day(10), 'cat.eating_out', 3650 + m * 120, eating[m % 3], from: card);
    await spend(day(24), 'cat.eating_out', 2280, eating[(m + 1) % 3], from: card);
    await spend(day(16), 'cat.shopping', 4999 + (m % 3) * 1500, 'Hometown Books', from: card);
    if (m % 2 == 0) await spend(day(19), 'cat.entertainment', 3200, 'Riverside Cinema', from: card);
    if (m == 2) await spend(day(13), 'cat.travel', 38900, 'Seaside Holidays', from: card);
    if (day(25).compareTo(now) <= 0) {
      await ledger.saveEntry(
        transferEntry(date: day(25), currency: 'GBP', fromId: bank, toId: card, fromAmount: 21000 + m * 900),
      );
    }
    if (day(26).compareTo(now) <= 0) {
      await ledger.saveEntry(
        transferEntry(date: day(26), currency: 'GBP', fromId: bank, toId: saver, fromAmount: 40000),
      );
      await spend(day(26), 'cat.interest', -1850 - m * 20, 'Example Bank', from: saver);
    }
  }

  for (final (cat, amount) in [
    ('cat.groceries', 26000),
    ('cat.eating_out', 9000),
    ('cat.shopping', 8000),
    ('cat.transport', 8000),
  ]) {
    await ledger.saveBudget(cat, amount);
  }
  await ledger.saveTargets({'equity': 6000, 'bond': 2500, 'cash': 1500});
  await ledger.savePlanned(
    label: 'Car insurance renewal',
    amount: -48000,
    date: addDays(now, 24),
    categoryId: 'cat.insurance',
  );
  await ledger.savePlanned(
    label: 'Annual bonus',
    amount: 150000,
    date: addDays(now, 52),
    categoryId: 'cat.bonus',
  );
}

/// Several component styles in the app theme (app bar title, rail labels,
/// buttons, chips) name no font family, so they take the platform's default
/// sans font. Tests have no such font (it draws boxes), so this names Inter,
/// the app's own font, for them.
class _InterEverywhere extends StatelessWidget {
  const _InterEverywhere({required this.child});
  final Widget child;

  static TextStyle? _f(TextStyle? s) => s?.copyWith(fontFamily: 'Inter', fontFamilyFallback: _fallback);

  // The bundled Inter has no arrows (→); the platform finds them in a
  // system font (see loadFonts).
  static const _fallback = ['SystemSans'];

  static WidgetStateProperty<TextStyle?>? _w(WidgetStateProperty<TextStyle?>? p) =>
      p == null ? null : WidgetStateProperty.resolveWith((states) => _f(p.resolve(states)));

  static ButtonStyle? _b(ButtonStyle? s) => s?.copyWith(textStyle: _w(s.textStyle));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Theme(
      data: t.copyWith(
        textTheme: t.textTheme.apply(fontFamilyFallback: _fallback),
        appBarTheme: t.appBarTheme.copyWith(titleTextStyle: _f(t.appBarTheme.titleTextStyle)),
        navigationBarTheme: t.navigationBarTheme.copyWith(
          labelTextStyle: _w(t.navigationBarTheme.labelTextStyle),
        ),
        navigationRailTheme: t.navigationRailTheme.copyWith(
          selectedLabelTextStyle: _f(t.navigationRailTheme.selectedLabelTextStyle),
          unselectedLabelTextStyle: _f(t.navigationRailTheme.unselectedLabelTextStyle),
        ),
        filledButtonTheme: FilledButtonThemeData(style: _b(t.filledButtonTheme.style)),
        outlinedButtonTheme: OutlinedButtonThemeData(style: _b(t.outlinedButtonTheme.style)),
        textButtonTheme: TextButtonThemeData(style: _b(t.textButtonTheme.style)),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: _b(t.segmentedButtonTheme.style),
          selectedIcon: t.segmentedButtonTheme.selectedIcon,
        ),
        floatingActionButtonTheme: t.floatingActionButtonTheme.copyWith(
          extendedTextStyle: _f(t.floatingActionButtonTheme.extendedTextStyle),
        ),
        inputDecorationTheme: t.inputDecorationTheme.copyWith(
          labelStyle: _f(t.inputDecorationTheme.labelStyle),
          floatingLabelStyle: _f(t.inputDecorationTheme.floatingLabelStyle),
          helperStyle: _f(t.inputDecorationTheme.helperStyle),
        ),
        listTileTheme: t.listTileTheme.copyWith(
          titleTextStyle: _f(t.listTileTheme.titleTextStyle),
          subtitleTextStyle: _f(t.listTileTheme.subtitleTextStyle),
          leadingAndTrailingTextStyle: _f(t.listTileTheme.leadingAndTrailingTextStyle),
        ),
        chipTheme: t.chipTheme.copyWith(
          labelStyle: _f(t.chipTheme.labelStyle),
          secondaryLabelStyle: _f(t.chipTheme.secondaryLabelStyle),
        ),
        dialogTheme: t.dialogTheme.copyWith(
          titleTextStyle: _f(t.dialogTheme.titleTextStyle),
          contentTextStyle: _f(t.dialogTheme.contentTextStyle),
        ),
        snackBarTheme: t.snackBarTheme.copyWith(contentTextStyle: _f(t.snackBarTheme.contentTextStyle)),
        tooltipTheme: t.tooltipTheme.copyWith(textStyle: _f(t.tooltipTheme.textStyle)),
        popupMenuTheme: t.popupMenuTheme.copyWith(textStyle: _f(t.popupMenuTheme.textStyle)),
      ),
      child: child,
    );
  }
}
