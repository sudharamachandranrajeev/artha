import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/shell.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'links.dart';
import 'onboarding_page.dart';
import 'pairing_dialogs.dart';
import 'providers.dart';

class ArthaApp extends StatelessWidget {
  const ArthaApp({super.key, this.home = const _Root()});
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Artha',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    home: home,
  );
}

/// Onboarding until a base currency exists, then the app. Also opens
/// `artha://` links the platform hands over (a scanned pairing code).
class _Root extends ConsumerStatefulWidget {
  const _Root();

  @override
  ConsumerState<_Root> createState() => _RootState();
}

class _RootState extends ConsumerState<_Root> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    PlatformLinks.listen(_open);
    PlatformLinks.initial().then((link) {
      if (link != null) _open(link);
    });
  }

  Future<void> _open(String link) async {
    // One at a time: a second scan while a dialog is up is ignored.
    if (_opening || !mounted) return;
    _opening = true;
    try {
      await openArthaLink(context, ref, link);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(setupProvider);
    // Keep the current screen while the provider reloads after each write.
    if (setup.hasValue) return setup.value == null ? const OnboardingPage() : const AppShell();
    if (setup.hasError) {
      return Scaffold(
        body: ErrorPanel(describeError(setup.error!), onRetry: () => ref.invalidate(baseCurrencyProvider)),
      );
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// Shown when the app cannot open its keys or database. Nothing is deleted:
/// the user is told what failed and can retry.
class StartupFailure extends StatelessWidget {
  const StartupFailure(this.error, {super.key, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ArthaApp(
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_outline, size: 48, color: Status.critical.color),
                  const SizedBox(height: 16),
                  Text(
                    'Artha could not open your data',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(describeError(error), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  const Text(
                    'Your data has not been changed or deleted. On Linux, check that the desktop keyring is '
                    'running and unlocked.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onRetry, child: const Text('Try again')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
