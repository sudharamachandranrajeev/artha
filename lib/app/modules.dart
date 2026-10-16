import 'package:flutter/material.dart';

import '../modules/finance/finance_module.dart';
import 'settings_page.dart';

/// One screen reachable from the navigation.
class Destination {
  const Destination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
    this.primary = false,
  });
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder page;

  /// Shown in the phone bottom bar; the rest sit under "More".
  final bool primary;

  /// Hint id for the navigation item.
  String get hint => 'nav.$id';
}

/// A part of the life ERP (finance today; documents, health... later). Each
/// module brings its own screens; the shell lists them in order.
class AppModule {
  const AppModule({required this.id, required this.name, required this.destinations});
  final String id;
  final String name;
  final List<Destination> destinations;
}

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
