import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/theme.dart';
import 'providers.dart';

/// The chosen palette and brightness mode, kept per device in local settings
/// (never synced): `ui.theme` and `ui.mode`.
class Appearance {
  const Appearance(this.themeId, this.mode);
  final String themeId;
  final ThemeMode mode;

  static const fallback = Appearance('indigo', ThemeMode.system);
}

final appearanceProvider = FutureProvider<Appearance>((ref) async {
  final db = ref.watch(sessionProvider).db;
  final id = await db.localSetting('ui.theme');
  final mode = await db.localSetting('ui.mode');
  return Appearance(id ?? Appearance.fallback.themeId, switch (mode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  });
});

ArthaPalette paletteOf(Appearance appearance) =>
    arthaPalettes.firstWhere((p) => p.id == appearance.themeId, orElse: () => arthaPalettes.first);

Future<void> setAppearance(WidgetRef ref, {String? themeId, ThemeMode? mode}) async {
  final db = ref.read(sessionProvider).db;
  if (themeId != null) await db.setLocalSetting('ui.theme', themeId);
  if (mode != null) await db.setLocalSetting('ui.mode', mode.name);
  ref.invalidate(appearanceProvider);
}
