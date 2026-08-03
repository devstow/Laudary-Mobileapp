import 'enums.dart';

/// A sellable service (ServiceListDto) shown on the "book a pickup" screen.
class ServiceItem {
  ServiceItem({
    required this.id,
    required this.name,
    this.category,
    this.description,
    required this.unit,
    required this.basePrice,
    required this.currency,
    this.displayOrder = 0,
  });

  final String id;
  final String name;
  final String? category;
  final String? description;
  final ServiceUnit unit;
  final double basePrice;
  final String currency;
  final int displayOrder;

  factory ServiceItem.fromJson(Map<String, dynamic> j) => ServiceItem(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        category: j['category'] as String?,
        description: j['description'] as String?,
        unit: ServiceUnit.from((j['unit'] as num?)?.toInt()),
        basePrice: (j['basePrice'] as num?)?.toDouble() ?? 0,
        currency: j['currency'] as String? ?? 'SAR',
        displayOrder: (j['displayOrder'] as num?)?.toInt() ?? 0,
      );
}
