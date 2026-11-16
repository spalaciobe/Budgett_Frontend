class Bank {
  final String id;
  final String name;
  final String code;
  final String? adjustmentRuleCutoff;
  final String? adjustmentRulePayment;
  final String defaultOffsetType;
  final bool allowsDateChange;
  final String? dateChangeFrequency;
  final String? logoUrl;
  final bool isActive;

  /// True when the bank bills purchases made on the cut-off day in the NEXT
  /// cycle instead of the one closing that day (Bancolombia does).
  final bool cutoffDayInNextCycle;

  Bank({
    required this.id,
    required this.name,
    required this.code,
    this.adjustmentRuleCutoff,
    this.adjustmentRulePayment,
    this.defaultOffsetType = 'calendario',
    this.allowsDateChange = false,
    this.dateChangeFrequency,
    this.logoUrl,
    this.isActive = true,
    this.cutoffDayInNextCycle = false,
  });

  factory Bank.fromJson(Map<String, dynamic> json) {
    return Bank(
      id: json['id'],
      name: json['nombre'],
      code: json['codigo'],
      adjustmentRuleCutoff: json['regla_ajuste_corte'],
      adjustmentRulePayment: json['regla_ajuste_pago'],
      defaultOffsetType: json['tipo_offset_default'] ?? 'calendario',
      allowsDateChange: json['permite_cambio_fecha'] ?? false,
      dateChangeFrequency: json['frecuencia_cambio_fecha'],
      logoUrl: json['logo_url'],
      isActive: json['activo'] ?? true,
      cutoffDayInNextCycle: json['dia_corte_en_siguiente_ciclo'] ?? false,
    );
  }
}
