import 'transaction.dart';

/// The VAT split printed on a Philippine-style receipt (Mercury Drug /
/// 7-Eleven style): VATable Sales, VAT-Exempt Sales, VAT (12%), and the
/// amount due.
///
/// Prices in MERQ are VAT-inclusive, so for an ordinary sale the total
/// is the gross, tax-in amount:
///   VATable Sales = total / 1.12
///   VAT (12%)     = total - VATable Sales
/// The two are rounded so that they always add back up to the total.
///
/// A Senior/PWD sale is VAT-exempt (checkout removes the VAT before
/// taking the 20% discount), so it shows VATable Sales 0.00 and
/// VAT 0.00, with the pre-discount net amount as VAT-Exempt Sales.
///
/// The Transaction only stores whole-sale figures — there is no
/// per-product VAT-exempt / zero-rated flag — so a Zero-Rated line is
/// not produced.
class VatBreakdown {
  static const double rate = 0.12;

  final double vatableSales;
  final double vatExemptSales;
  final double vatAmount;
  final double amountDue;

  const VatBreakdown({
    required this.vatableSales,
    required this.vatExemptSales,
    required this.vatAmount,
    required this.amountDue,
  });

  /// [decimals] = the active currency's decimal places (2 for PHP).
  factory VatBreakdown.fromTransaction(Transaction t, {int decimals = 2}) {
    double round(double v) => double.parse(v.toStringAsFixed(decimals));

    if (t.hasDiscount) {
      final subtotal = t.total + t.discountAmount + t.vatExemptAmount;
      return VatBreakdown(
        vatableSales: 0,
        vatExemptSales: round(subtotal - t.vatExemptAmount),
        vatAmount: 0,
        amountDue: t.total,
      );
    }

    final vatable = round(t.total / (1 + rate));
    final vat = round(t.total - vatable);
    return VatBreakdown(
      vatableSales: vatable,
      vatExemptSales: 0,
      vatAmount: vat,
      amountDue: t.total,
    );
  }
}
