/// One laundry in the public directory (GET /api/public/tenants, GET /api/public/tenants/{id}).
class TenantDirectoryItem {
  TenantDirectoryItem({
    required this.id,
    required this.name,
    this.logoUrl,
    this.address,
    this.countryCode,
    this.defaultLanguage = 'en',
    this.defaultCurrency = 'SAR',
    this.appName,
    this.tagline,
    this.primaryColor,
  });

  /// Tenant id (GUID) — sent as `tenantId` on registration / email+phone checks.
  final String id;
  final String name;
  final String? logoUrl;
  final String? address;
  final String? countryCode;
  final String defaultLanguage;
  final String defaultCurrency;
  final String? appName;
  final String? tagline;
  final String? primaryColor;

  /// Display name for branding — the tenant's app name, else its business name.
  String get displayName => (appName != null && appName!.isNotEmpty) ? appName! : name;

  factory TenantDirectoryItem.fromJson(Map<String, dynamic> j) => TenantDirectoryItem(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        logoUrl: j['logoUrl'] as String?,
        address: j['address'] as String?,
        countryCode: j['countryCode'] as String?,
        defaultLanguage: (j['defaultLanguage'] as String?) ?? 'en',
        defaultCurrency: (j['defaultCurrency'] as String?) ?? 'SAR',
        appName: j['appName'] as String?,
        tagline: j['tagline'] as String?,
        primaryColor: j['primaryColor'] as String?,
      );
}

/// One business offered by a 409 TenantSelectionRequired login response.
class TenantChoice {
  TenantChoice({required this.tenantId, required this.name, this.logoUrl});
  final String tenantId;
  final String name;
  final String? logoUrl;

  factory TenantChoice.fromJson(Map<String, dynamic> j) => TenantChoice(
        tenantId: j['tenantId'] as String,
        name: (j['name'] as String?) ?? '',
        logoUrl: j['logoUrl'] as String?,
      );
}
