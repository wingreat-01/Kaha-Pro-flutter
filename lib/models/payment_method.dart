class PaymentMethod {
  final String id;
  final String storeId;
  final String name;
  final bool isActive;
  final int sortOrder;

  PaymentMethod({
    required this.id,
    required this.storeId,
    required this.name,
    required this.isActive,
    required this.sortOrder,
  });

  factory PaymentMethod.fromMap(Map<String, dynamic> map) {
    return PaymentMethod(
      id: map['id'] as String,
      storeId: map['store_id'] as String,
      name: map['name'] as String,
      isActive: map['is_active'] as bool? ?? true,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'name': name,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
  }

  PaymentMethod copyWith({
    String? id,
    String? storeId,
    String? name,
    bool? isActive,
    int? sortOrder,
  }) {
    return PaymentMethod(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
