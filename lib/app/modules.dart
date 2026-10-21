import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';

import '../modules/finance/finance_module.dart';
import 'settings_page.dart';

final modules = <AppModule>[financeModule];

/// Settings is app-wide, so it comes after every module's screens.
final settingsDestination = Destination(
  id: 'settings',
  label: 'Settings',
  icon: Icons.settings_outlined,
  selectedIcon: Icons.settings,
  page: (_) => const SettingsPage(),
);

List<Destination> get allDestinations => [for (final m in modules) ...m.destinations, settingsDestination];
