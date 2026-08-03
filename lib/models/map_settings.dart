/// Tenant map defaults (MapSettingsDto) — where the pickup-pin picker centres and
/// which country geocoding is biased to. Falls back to Riyadh, KSA.
class MapSettings {
  MapSettings({
    required this.countryCode,
    required this.defaultLat,
    required this.defaultLng,
  });

  final String countryCode; // ISO-3166 alpha-2, e.g. "SA"
  final double defaultLat;
  final double defaultLng;

  /// Default centre (Riyadh) used only if the tenant map-settings call fails. `countryCode`
  /// is EMPTY = worldwide geocoding with no country bias — exactly like the web, which only
  /// biases when the tenant explicitly configures a search country.
  static final fallback = MapSettings(countryCode: '', defaultLat: 24.7136, defaultLng: 46.6753);

  factory MapSettings.fromJson(Map<String, dynamic> j) => MapSettings(
        // Empty when the tenant hasn't set a country → worldwide search (do NOT force a country).
        countryCode: (j['searchCountryCode'] as String?)?.trim() ?? '',
        defaultLat: (j['defaultLatitude'] as num?)?.toDouble() ?? fallback.defaultLat,
        defaultLng: (j['defaultLongitude'] as num?)?.toDouble() ?? fallback.defaultLng,
      );
}
