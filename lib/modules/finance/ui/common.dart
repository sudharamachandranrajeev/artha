import 'dart:convert';

import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';

import '../../../db/database.dart';
import '../domain/accounting.dart';

extension AccountX on Account {
  AccountKind get accountKind => accountKindOf(kind);
  Subtype get type => subtypeOf(subtype);
  bool get isCategory => kind == 'income' || kind == 'expense';

  /// The user's own accounts: not categories and not equity.
  bool get isReal => kind == 'asset' || kind == 'liability';
  Map<String, Object?> get metaMap => (jsonDecode(meta) as Map).cast<String, Object?>();
  bool get essential => metaMap['essential'] == true;

  /// Balance as people read it: owed and earned are positive.
  int natural(int raw) => naturalSign(accountKind, raw);
  int raw(int natural) => naturalSign(accountKind, natural);
}

extension CommodityX on Commodity {
  bool get isCurrency => kind == 'currency';
}

/// Scale of a commodity id: a currency's minor unit, a security's units.
/// Ticker or currency codes for commodity ids, for messages.
String codesOf(Map<String, Commodity> commodities, Iterable<String> ids) =>
    [for (final id in ids) commodities[id]?.code ?? id].join(', ');

int scaleOf(Map<String, Commodity> commodities, String id) =>
    commodities[id]?.scale ?? currencyInfo(id).scale;

IconData subtypeIcon(String id) => switch (id) {
  'current' => Icons.account_balance_outlined,
  'savings' || 'isa_cash' => Icons.savings_outlined,
  'cash' => Icons.payments_outlined,
  'forex' => Icons.currency_exchange,
  'isa_stocks' || 'lisa' || 'isa_ifi' || 'brokerage' => Icons.trending_up,
  'bonds' => Icons.receipt_long_outlined,
  'pension' => Icons.elderly_outlined,
  'crypto' => Icons.currency_bitcoin,
  'security' => Icons.show_chart,
  'property' => Icons.home_outlined,
  'receivable' => Icons.call_received,
  'credit_card' => Icons.credit_card,
  'loan' || 'mortgage' || 'overdraft' || 'bnpl' || 'payable' => Icons.request_quote_outlined,
  'income' => Icons.south_west,
  'expense' => Icons.north_east,
  _ => Icons.account_balance_wallet_outlined,
};

const groupLabels = {
  'liquid': 'Cash and bank',
  'invested': 'Investments',
  'property': 'Property',
  'other': 'Other assets',
  'debt': 'Debts',
};

/// A dropdown over [accounts]; shows the currency next to each name.
class AccountField extends StatelessWidget {
  const AccountField({
    super.key,
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.label = 'Account',
    this.showCurrency = true,
  });
  final List<Account> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final bool showCurrency;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('$label/$value/${accounts.length}'),
    initialValue: accounts.any((a) => a.id == value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final a in accounts)
        DropdownMenuItem(
          value: a.id,
          child: Text(
            showCurrency && !a.isCategory
                ? '${a.name} · ${a.commodityId.length == 3 ? a.commodityId : 'units'}'
                : a.name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: onChanged,
    validator: (v) => v == null ? 'Choose one' : null,
  );
}

/// Currency dropdown over every known ISO code.
class CurrencyField extends StatelessWidget {
  const CurrencyField({super.key, required this.value, required this.onChanged, this.label = 'Currency'});
  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('$label/$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final c in currencies.values)
        DropdownMenuItem(
          value: c.code,
          child: Text('${c.code} · ${c.name}', overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (v) => v == null ? null : onChanged(v),
  );
}
