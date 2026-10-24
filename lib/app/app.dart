import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/theme.dart';
import 'appearance.dart';
import 'modules.dart';
import 'onboarding_page.dart';
import 'providers.dart';

class ArthaApp extends ConsumerWidget {
  const ArthaApp({super.key, this.home = const _Root()});
  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider).value ?? Appearance.fallback;
    final palette = paletteOf(appearance);
    return MaterialApp(
      title: 'Artha',
      debugShowCheckedModeBanner: false,
      theme: buildArthaTheme(palette, Brightness.light),
      darkTheme: buildArthaTheme(palette, Brightness.dark),
      themeMode: appearance.mode,
      home: home,
    );
  }
}

/// The theme for the chosen palette.
ThemeData arthaTheme(WidgetRef ref, Brightness brightness) =>
    buildArthaTheme(paletteOf(ref.watch(appearanceProvider).value ?? Appearance.fallback), brightness);

/// The daily exchange-rate refresh.
void startRateRefresh(WidgetRef ref) => Future.microtask(() => ref.read(fxAutoProvider.future)).ignore();

/// Opens the links the platform hands over (a scanned pairing code).
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) => const LinkHandler(child: ArthaHome());
}

/// Onboarding until a base currency exists, then the app. [onHome] leads
/// back to the Brahma suite's home screen when the suite hosts Artha (which
/// starts the rate refresh itself).
class ArthaHome extends ConsumerWidget {
  const ArthaHome({super.key, this.onHome});
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(setupProvider);
    // Keep the current screen while the provider reloads after each write.
    if (setup.hasValue) {
      return setup.value == null
          ? const OnboardingPage()
          : AppShell(
              destinations: allDestinations,
              onStart: onHome == null ? startRateRefresh : null,
              onHome: onHome,
            );
    }
    if (setup.hasError) {
      return Scaffold(
        body: ErrorPanel(describeError(setup.error!), onRetry: () => ref.invalidate(baseCurrencyProvider)),
      );
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
