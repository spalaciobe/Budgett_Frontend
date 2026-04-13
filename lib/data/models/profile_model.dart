class ProfileModel {
  final String id;
  final String? username;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? currencySymbol;

  ProfileModel({
    required this.id,
    this.username,
    this.firstName,
    this.lastName,
    this.phone,
    this.currencySymbol,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] as String,
      username: json['username'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      phone: json['phone'] as String?,
      currencySymbol: json['currency_symbol'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'currency_symbol': currencySymbol,
      };
}
