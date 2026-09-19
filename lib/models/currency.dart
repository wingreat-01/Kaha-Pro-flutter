/// One currency the store can sell in. Purely a display/formatting
/// concern — amounts stored on products and transactions are plain
/// numbers and are never converted when the currency changes.
class Currency {
  /// ISO 4217 code ('PHP', 'USD'…). This is what gets persisted.
  final String code;

  /// What shows in front of an amount ('₱', '$', 'Rp'…).
  final String symbol;

  final String name;

  /// Digits after the decimal point (2 for PHP/USD, 0 for JPY/IDR…).
  final int decimals;

  /// Common cash notes, ascending — drives the checkout quick-amount
  /// chips (the "+₱100" style buttons).
  final List<double> bills;

  /// For a total that doesn't line up with a note, the chips also offer
  /// the total rounded up to a multiple of this (₱220 -> ₱300).
  final double stackStep;

  /// Once the total is above the largest note, no single note covers
  /// it, so the chips switch to "round up to the next N" targets using
  /// these steps.
  final List<double> roundUpSteps;

  const Currency({
    required this.code,
    required this.symbol,
    required this.name,
    this.decimals = 2,
    required this.bills,
    required this.stackStep,
    required this.roundUpSteps,
  });

  double get largestBill => bills.last;

  /// Symbol as it sits in front of a number: letter-based symbols get a
  /// space ("Rp 1500", "AED 25.00"), sign-based ones don't ("₱25.00").
  String get prefix =>
      RegExp(r'[A-Za-z]$').hasMatch(symbol) ? '$symbol ' : symbol;

  /// Hint text for a price field ('0.00', or '0' for whole-unit currencies).
  String get zeroHint => decimals == 0 ? '0' : '0.'.padRight(2 + decimals, '0');

  /// Number only, no symbol — for receipt columns. Negatives get a
  /// leading "-".
  String plain(num amount) {
    final text = amount.abs().toStringAsFixed(decimals);
    return amount < 0 ? '-$text' : text;
  }

  /// Full display string: "₱1250.00", "-₱50.00", "Rp 15000".
  String format(num amount) {
    final text = '$prefix${amount.abs().toStringAsFixed(decimals)}';
    return amount < 0 ? '-$text' : text;
  }
}

class Currencies {
  Currencies._();

  static const php = Currency(
    code: 'PHP',
    symbol: '₱',
    name: 'Philippine Peso',
    bills: [20, 50, 100, 500, 1000],
    stackStep: 100,
    roundUpSteps: [50, 100, 500],
  );

  static const usd = Currency(
    code: 'USD',
    symbol: r'$',
    name: 'US Dollar',
    bills: [1, 5, 10, 20, 50, 100],
    stackStep: 10,
    roundUpSteps: [5, 10, 20],
  );

  static const eur = Currency(
    code: 'EUR',
    symbol: '€',
    name: 'Euro',
    bills: [5, 10, 20, 50, 100],
    stackStep: 10,
    roundUpSteps: [5, 10, 20],
  );

  static const gbp = Currency(
    code: 'GBP',
    symbol: '£',
    name: 'British Pound',
    bills: [5, 10, 20, 50],
    stackStep: 10,
    roundUpSteps: [5, 10, 20],
  );

  static const jpy = Currency(
    code: 'JPY',
    symbol: '¥',
    name: 'Japanese Yen',
    decimals: 0,
    bills: [1000, 5000, 10000],
    stackStep: 1000,
    roundUpSteps: [500, 1000, 5000],
  );

  static const sgd = Currency(
    code: 'SGD',
    symbol: r'S$',
    name: 'Singapore Dollar',
    bills: [2, 5, 10, 50, 100],
    stackStep: 10,
    roundUpSteps: [5, 10, 50],
  );

  static const myr = Currency(
    code: 'MYR',
    symbol: 'RM',
    name: 'Malaysian Ringgit',
    bills: [1, 5, 10, 50, 100],
    stackStep: 10,
    roundUpSteps: [5, 10, 50],
  );

  static const idr = Currency(
    code: 'IDR',
    symbol: 'Rp',
    name: 'Indonesian Rupiah',
    decimals: 0,
    bills: [2000, 5000, 10000, 20000, 50000, 100000],
    stackStep: 10000,
    roundUpSteps: [5000, 10000, 50000],
  );

  static const thb = Currency(
    code: 'THB',
    symbol: '฿',
    name: 'Thai Baht',
    bills: [20, 50, 100, 500, 1000],
    stackStep: 100,
    roundUpSteps: [50, 100, 500],
  );

  static const vnd = Currency(
    code: 'VND',
    symbol: '₫',
    name: 'Vietnamese Dong',
    decimals: 0,
    bills: [10000, 20000, 50000, 100000, 200000, 500000],
    stackStep: 100000,
    roundUpSteps: [10000, 50000, 100000],
  );

  static const inr = Currency(
    code: 'INR',
    symbol: '₹',
    name: 'Indian Rupee',
    bills: [10, 20, 50, 100, 200, 500],
    stackStep: 100,
    roundUpSteps: [50, 100, 500],
  );

  static const aud = Currency(
    code: 'AUD',
    symbol: r'A$',
    name: 'Australian Dollar',
    bills: [5, 10, 20, 50, 100],
    stackStep: 10,
    roundUpSteps: [5, 10, 20],
  );

  static const cad = Currency(
    code: 'CAD',
    symbol: r'C$',
    name: 'Canadian Dollar',
    bills: [5, 10, 20, 50, 100],
    stackStep: 10,
    roundUpSteps: [5, 10, 20],
  );

  static const krw = Currency(
    code: 'KRW',
    symbol: '₩',
    name: 'South Korean Won',
    decimals: 0,
    bills: [1000, 5000, 10000, 50000],
    stackStep: 10000,
    roundUpSteps: [1000, 5000, 10000],
  );

  static const hkd = Currency(
    code: 'HKD',
    symbol: r'HK$',
    name: 'Hong Kong Dollar',
    bills: [20, 50, 100, 500, 1000],
    stackStep: 100,
    roundUpSteps: [50, 100, 500],
  );

  static const cny = Currency(
    code: 'CNY',
    symbol: 'CN¥',
    name: 'Chinese Yuan',
    bills: [1, 5, 10, 20, 50, 100],
    stackStep: 10,
    roundUpSteps: [5, 10, 50],
  );

  static const aed = Currency(
    code: 'AED',
    symbol: 'AED',
    name: 'UAE Dirham',
    bills: [5, 10, 20, 50, 100, 200, 500, 1000],
    stackStep: 100,
    roundUpSteps: [50, 100, 500],
  );

  /// Order = order shown in the picker. PHP first (the app's default).
  static const all = <Currency>[
    php, usd, eur, gbp, jpy, sgd, myr, idr, thb, vnd, inr, aud, cad, krw, hkd, cny, aed,
  ];

  /// Unknown / missing code falls back to PHP so a bad saved value
  /// can never leave the UI without a currency.
  static Currency byCode(String? code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    return php;
  }
}
