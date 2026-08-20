import 'enums.dart';

/// A sellable service (ServiceListDto) shown on the "book a pickup" screen.
class ServiceItem {
  ServiceItem({
    required this.id,
    required this.name,
    this.category,
    this.imageUrl,
    this.description,
    required this.unit,
    required this.basePrice,
    required this.currency,
    this.displayOrder = 0,
  });

  final String id;
  final String name;

  /// Managed category name (falls back to the legacy free-text category).
  final String? category;

  /// Relative or absolute image URL; resolve with AppConfig.mediaUrl before loading.
  final String? imageUrl;
  final String? description;
  final ServiceUnit unit;
  final double basePrice;
  final String currency;
  final int displayOrder;

  factory ServiceItem.fromJson(Map<String, dynamic> j) => ServiceItem(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        // Prefer the managed category name; fall back to the deprecated free-text field.
        category: (j['categoryName'] as String?) ?? (j['category'] as String?),
        imageUrl: j['imageUrl'] as String?,
        description: j['description'] as String?,
        unit: ServiceUnit.from((j['unit'] as num?)?.toInt()),
        basePrice: (j['basePrice'] as num?)?.toDouble() ?? 0,
        currency: j['currency'] as String? ?? 'SAR',
        displayOrder: (j['displayOrder'] as num?)?.toInt() ?? 0,
      );
}
