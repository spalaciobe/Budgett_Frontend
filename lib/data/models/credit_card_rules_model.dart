enum CutoffType { fixed, relative }
enum PaymentType { fixed, relativeDays }
enum OffsetType { calendar, business }
enum RelativeCutoffType { lastBusinessDay, secondToLastBusinessDay, firstBusinessDay }

class CreditCardRules {
  final String id;
  final String accountId;
  final String bankId;
  final CutoffType cutoffType;
  final int? nominalCutoffDay; // 1-31
  final RelativeCutoffType? relativeCutoffType;
  final int? relativeCutoffOffset;
  final PaymentType paymentType;
  final int? nominalPaymentDay; // 1-31
  final String? paymentMonth; // 'same' | 'next'
  final int? daysAfterCutoff;
  final OffsetType paymentOffsetType;

  CreditCardRules({
    required this.id,
    required this.accountId,
    required this.bankId,
    required this.cutoffType,
    this.nominalCutoffDay,
    this.relativeCutoffType,
    this.relativeCutoffOffset,
    required this.paymentType,
    this.nominalPaymentDay,
    this.paymentMonth,
    this.daysAfterCutoff,
    this.paymentOffsetType = OffsetType.calendar,
  });

  factory CreditCardRules.fromJson(Map<String, dynamic> json) {
    return CreditCardRules(
      id: json['id'],
      accountId: json['account_id'],
      bankId: json['banco_id'],
      cutoffType: _parseCutoffType(json['tipo_corte']),
      nominalCutoffDay: json['dia_corte_nominal'],
      relativeCutoffType: _parseRelativeCutoffType(json['corte_relativo_tipo']),
      relativeCutoffOffset: json['corte_relativo_offset'],
      paymentType: _parsePaymentType(json['tipo_pago']),
      nominalPaymentDay: json['dia_pago_nominal'],
      paymentMonth: json['mes_pago'],
      daysAfterCutoff: json['dias_despues_corte'],
      paymentOffsetType: _parseOffsetType(json['tipo_offset_pago']),
    );
  }

  static CutoffType _parseCutoffType(String? value) {
    return value == 'relativo' ? CutoffType.relative : CutoffType.fixed;
  }

  static PaymentType _parsePaymentType(String? value) {
    return value == 'relativo_dias' ? PaymentType.relativeDays : PaymentType.fixed;
  }

  static OffsetType _parseOffsetType(String? value) {
    return value == 'habiles' ? OffsetType.business : OffsetType.calendar;
  }

  static RelativeCutoffType? _parseRelativeCutoffType(String? value) {
    switch (value) {
      case 'ultimo_dia_habil':
        return RelativeCutoffType.lastBusinessDay;
      case 'penultimo_dia_habil':
        return RelativeCutoffType.secondToLastBusinessDay;
      case 'primer_dia_habil':
        return RelativeCutoffType.firstBusinessDay;
      default:
        return null; // Or throw exception if strict
    }
  }
}
