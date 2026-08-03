/// The customer's editable profile (CustomerProfileModel).
class CustomerProfile {
  CustomerProfile({required this.fullName, this.phone, this.email, this.address, this.city, this.photoUrl});
  final String fullName;
  final String? phone;
  final String? email;
  final String? address;
  final String? city;
  final String? photoUrl;

  factory CustomerProfile.fromJson(Map<String, dynamic> j) => CustomerProfile(
        fullName: j['fullName'] as String? ?? '',
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        address: j['address'] as String?,
        city: j['city'] as String?,
        photoUrl: j['photoUrl'] as String?,
      );

  // Email is the login identity and is read-only — never sent back on profile update
  // (the server also ignores it defensively).
  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (city != null) 'city': city,
      };
}
