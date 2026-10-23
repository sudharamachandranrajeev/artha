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

/// Onboarding until a base currency exists, then the app. Also opens the
/// links the platform hands over (a scanned pairing code).
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) => LinkHandler(child: _home(ref));

  Widget _home(WidgetRef ref) {
    final setup = ref.watch(setupProvider);
    // Keep the current screen while the provider reloads after each write.
    if (setup.hasValue) {
      return setup.value == null
          ? const OnboardingPage()
          : AppShell(
              destinations: allDestinations,
              // The daily exchange-rate refresh.
              onStart: (ref) => Future.microtask(() => ref.read(fxAutoProvider.future)).ignore(),
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
