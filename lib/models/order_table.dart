/// A physical table in the store, one QR code each — backed by the
/// `tables` Supabase table from the QR-ordering migration
/// (20260928_020_qr_ordering_core.sql).
class OrderTable {
  final String id;
  final String label;
  final String qrToken;
  final bool isActive;

  const OrderTable({
    required this.id,
    required this.label,
    required this.qrToken,
    required this.isActive,
  });
}
