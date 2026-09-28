/// Config for the QR-ordering customer page (order.html), hosted
/// alongside privacy.html / delete-account.html / reset-password.html
/// on merq.prohubapps.com.
///
/// If order.html ends up served at a rewritten path instead (e.g.
/// merq.prohubapps.com/order/<token>), update [orderPageBaseUrl] and
/// [buildOrderUrl] together — the query-string form below is what
/// works with zero server config, since it doesn't depend on the host
/// supporting path rewrites.
class QrOrderingConfig {
  static const orderPageBaseUrl = 'https://merq.prohubapps.com/order/index.html';

  static String buildOrderUrl(String qrToken) {
    final separator = orderPageBaseUrl.contains('?') ? '&' : '?';
    return '$orderPageBaseUrl${separator}t=$qrToken';
  }
}
