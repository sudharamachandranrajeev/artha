/// ISO 4217 currencies Artha knows how to scale and label. Any other code can
/// still be used; it defaults to 2 decimals and shows its code as the symbol.
class CurrencyInfo {
  const CurrencyInfo(this.code, this.name, this.symbol, [this.scale = 2]);
  final String code;
  final String name;
  final String symbol;

  /// Decimal places of the minor unit (GBP 2, JPY 0, KWD 3).
  final int scale;
}

const _list = <CurrencyInfo>[
  CurrencyInfo('GBP', 'British pound', '£'),
  CurrencyInfo('EUR', 'Euro', '€'),
  CurrencyInfo('USD', 'US dollar', r'$'),
  CurrencyInfo('INR', 'Indian rupee', '₹'),
  CurrencyInfo('AED', 'UAE dirham', 'AED '),
  CurrencyInfo('AUD', 'Australian dollar', r'A$'),
  CurrencyInfo('BGN', 'Bulgarian lev', 'лв '),
  CurrencyInfo('BHD', 'Bahraini dinar', 'BHD ', 3),
  CurrencyInfo('BRL', 'Brazilian real', r'R$'),
  CurrencyInfo('CAD', 'Canadian dollar', r'C$'),
  CurrencyInfo('CHF', 'Swiss franc', 'CHF '),
  CurrencyInfo('CNY', 'Chinese yuan', '¥'),
  CurrencyInfo('CZK', 'Czech koruna', 'Kč '),
  CurrencyInfo('DKK', 'Danish krone', 'kr '),
  CurrencyInfo('HKD', 'Hong Kong dollar', r'HK$'),
  CurrencyInfo('HUF', 'Hungarian forint', 'Ft '),
  CurrencyInfo('IDR', 'Indonesian rupiah', 'Rp '),
  CurrencyInfo('ILS', 'Israeli shekel', '₪'),
  CurrencyInfo('ISK', 'Icelandic króna', 'kr ', 0),
  CurrencyInfo('JPY', 'Japanese yen', '¥', 0),
  CurrencyInfo('KRW', 'South Korean won', '₩', 0),
  CurrencyInfo('KWD', 'Kuwaiti dinar', 'KWD ', 3),
  CurrencyInfo('LKR', 'Sri Lankan rupee', 'Rs '),
  CurrencyInfo('MXN', 'Mexican peso', r'MX$'),
  CurrencyInfo('MYR', 'Malaysian ringgit', 'RM '),
  CurrencyInfo('NOK', 'Norwegian krone', 'kr '),
  CurrencyInfo('NZD', 'New Zealand dollar', r'NZ$'),
  CurrencyInfo('OMR', 'Omani rial', 'OMR ', 3),
  CurrencyInfo('PHP', 'Philippine peso', '₱'),
  CurrencyInfo('PKR', 'Pakistani rupee', 'Rs '),
  CurrencyInfo('PLN', 'Polish złoty', 'zł '),
  CurrencyInfo('QAR', 'Qatari riyal', 'QAR '),
  CurrencyInfo('RON', 'Romanian leu', 'lei '),
  CurrencyInfo('SAR', 'Saudi riyal', 'SAR '),
  CurrencyInfo('SEK', 'Swedish krona', 'kr '),
  CurrencyInfo('SGD', 'Singapore dollar', r'S$'),
  CurrencyInfo('THB', 'Thai baht', '฿'),
  CurrencyInfo('TRY', 'Turkish lira', '₺'),
  CurrencyInfo('ZAR', 'South African rand', 'R '),
];

final Map<String, CurrencyInfo> currencies = {for (final c in _list) c.code: c};

CurrencyInfo currencyInfo(String code) => currencies[code] ?? CurrencyInfo(code, code, '$code ');

/// Currencies the European Central Bank publishes daily reference rates for
/// (the free Frankfurter API mirrors them).
const ecbCurrencies = {
  'AUD',
  'BGN',
  'BRL',
  'CAD',
  'CHF',
  'CNY',
  'CZK',
  'DKK',
  'EUR',
  'GBP',
  'HKD',
  'HUF',
  'IDR',
  'ILS',
  'INR',
  'ISK',
  'JPY',
  'KRW',
  'MXN',
  'MYR',
  'NOK',
  'NZD',
  'PHP',
  'PLN',
  'RON',
  'SEK',
  'SGD',
  'THB',
  'TRY',
  'USD',
  'ZAR',
};
