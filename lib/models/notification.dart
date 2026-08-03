/// A single in-app notification (NotificationItemDto).
class AppNotification {
  AppNotification({
    required this.id,
    required this.title,
    this.body,
    this.url,
    required this.icon,
    required this.color,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String? body;
  final String? url;
  final String icon;   // server hint (e.g. tabler icon name) — mapped to a Material icon in UI
  final String color;
  final bool isRead;
  final DateTime createdAt;

  /// The order this notification refers to, if any — extracted from the deep-link url
  /// (e.g. "/Portal/Details/{guid}"). Drives "tap → order tracking" for CUSTOMERS.
  String? get orderId {
    if (url == null) return null;
    final m = RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').firstMatch(url!);
    return m?.group(0);
  }

  /// The order NUMBER referenced in the title/body (e.g. "ORD-000012"). DRIVER notifications
  /// deep-link to "/DriverPortal" with no id, but name the order number — used to open the task.
  String? get orderNumberRef {
    final m = RegExp(r'ORD-\d+').firstMatch('$title ${body ?? ''}');
    return m?.group(0);
  }

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        body: j['body'] as String?,
        url: j['url'] as String?,
        icon: j['icon'] as String? ?? '',
        color: j['color'] as String? ?? '',
        isRead: j['isRead'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );
}
