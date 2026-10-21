import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';

import 'ui/accounts_page.dart';
import 'ui/dashboard_page.dart';
import 'ui/import_page.dart';
import 'ui/insights_page.dart';
import 'ui/portfolio_page.dart';
import 'ui/reports_page.dart';
import 'ui/transactions_page.dart';

final financeModule = AppModule(
  id: 'finance',
  name: 'Finance',
  destinations: [
    Destination(
      id: 'dashboard',
      label: 'Dashboard',
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard,
      primary: true,
      page: (_) => const DashboardPage(),
    ),
    Destination(
      id: 'accounts',
      label: 'Accounts',
      icon: Icons.account_balance_outlined,
      selectedIcon: Icons.account_balance,
      primary: true,
      page: (_) => const AccountsPage(),
    ),
    Destination(
      id: 'transactions',
      label: 'Transactions',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      primary: true,
      page: (_) => const TransactionsPage(),
    ),
    Destination(
      id: 'portfolio',
      label: 'Portfolio',
      icon: Icons.pie_chart_outline,
      selectedIcon: Icons.pie_chart,
      primary: true,
      page: (_) => const PortfolioPage(),
    ),
    Destination(
      id: 'insights',
      label: 'Insights',
      icon: Icons.lightbulb_outline,
      selectedIcon: Icons.lightbulb,
      page: (_) => const InsightsPage(),
    ),
    Destination(
      id: 'reports',
      label: 'Reports',
      icon: Icons.summarize_outlined,
      selectedIcon: Icons.summarize,
      page: (_) => const ReportsPage(),
    ),
    Destination(
      id: 'import',
      label: 'Import',
      icon: Icons.upload_file_outlined,
      selectedIcon: Icons.upload_file,
      page: (_) => const ImportPage(),
    ),
  ],
);
