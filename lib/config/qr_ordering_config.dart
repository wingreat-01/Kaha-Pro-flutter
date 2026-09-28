/// Config for the QR-ordering customer page (order.html), hosted
/// alongside privacy.html / delete-account.html / reset-password.html
/// on merq.prohubapps.com — order.html lives at the site root, same
/// level as those files (not in a subfolder), so the URL below points
/// straight at it.
///
/// If order.html ever moves (e.g. into a rewritten /order/<token>
/// path), update [orderPageBaseUrl] and [buildOrderUrl] together, and
/// regenerate every table's QR code — existing ones will point at the
/// old location.
class QrOrderingConfig {
  static const orderPageBaseUrl = 'https://merq.prohubapps.com/order.html';

  static String buildOrderUrl(String qrToken) {
    final separator = orderPageBaseUrl.contains('?') ? '&' : '?';
    return '$orderPageBaseUrl${separator}t=$qrToken';
  }
}
