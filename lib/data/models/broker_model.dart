class Broker {
  final String id;
  final String name;
  final String code;
  final List<String> supportedTypes;
  final String defaultCurrency;
  final String? logoUrl;
  final String? websiteUrl;
  final bool isActive;

  Broker({
    required this.id,
    required this.name,
    required this.code,
    required this.supportedTypes,
    this.defaultCurrency = 'COP',
    this.logoUrl,
    this.websiteUrl,
    this.isActive = true,
  });

  factory Broker.fromJson(Map<String, dynamic> json) {
    return Broker(
      id: json['id'],
      name: json['nombre'],
      code: json['codigo'],
      supportedTypes: (json['supported_types'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      defaultCurrency: json['default_currency'] ?? 'COP',
      logoUrl: json['logo_url'],
      websiteUrl: json['website_url'],
      isActive: json['activo'] ?? true,
    );
  }
}
