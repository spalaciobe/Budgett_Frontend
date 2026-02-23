class Holiday {
  final DateTime date;
  final String name;
  final String type; // fixed, movil, variable
  final DateTime? originalDate;
  final bool isMoved;

  Holiday({
    required this.date,
    required this.name,
    required this.type,
    this.originalDate,
    this.isMoved = false,
  });

  factory Holiday.fromJson(Map<String, dynamic> json) {
    return Holiday(
      date: DateTime.parse(json['fecha']),
      name: json['nombre'],
      type: json['tipo'],
      originalDate: json['fecha_original'] != null ? DateTime.parse(json['fecha_original']) : null,
      isMoved: json['trasladado'] ?? false,
    );
  }
}
