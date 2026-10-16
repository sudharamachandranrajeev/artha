import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/session.dart';
import 'core/security/key_vault.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _start();
}

Future<void> _start() async {
  try {
    final session = await AppSession.open(KeyVault(const DeviceSecretStore()));
    runApp(
      ProviderScope(
        overrides: [sessionProvider.overrideWithValue(session)],
        // Failures are shown with a retry button; silent retries would hide them.
        retry: (_, _) => null,
        child: const ArthaApp(),
      ),
    );
  } catch (e) {
    runApp(StartupFailure(e, onRetry: _start));
  }
}
