import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Models under test
import 'package:budgett_frontend/data/models/bank_model.dart';

// ---------------------------------------------------------------------------
// Helper: create a Bank instance from raw JSON (mirrors DB structure)
// ---------------------------------------------------------------------------
Bank _bankFromCode(String code, String name) {
  return Bank.fromJson({
    'id': 'id-$code',
    'nombre': name,
    'codigo': code,
    'regla_ajuste_corte': null,
    'regla_ajuste_pago': null,
    'tipo_offset_default': 'calendario',
    'permite_cambio_fecha': false,
    'frecuencia_cambio_fecha': null,
    'logo_url': null,
    'activo': true,
  });
}

// ---------------------------------------------------------------------------
// Inline: credit-card rules builder (mirrors BankOnboardingScreen logic)
// ---------------------------------------------------------------------------
Map<String, dynamic> buildCreditCardRules({
  required Bank bank,
  int? cutoffDay,
  int? paymentDay,
}) {
  switch (bank.code) {
    case 'RAPPICARD':
      return {
        'banco_id': bank.id,
        'tipo_corte': 'relativo',
        'corte_relativo_tipo': 'penultimo_dia_habil',
        'tipo_pago': 'relativo_dias',
        'dias_despues_corte': 10,
        'tipo_offset_pago': 'calendario',
      };
    case 'NUBANK':
      return {
        'banco_id': bank.id,
        'tipo_corte': 'fijo',
        'dia_corte_nominal': cutoffDay ?? 25,
        'tipo_pago': 'fijo',
        'dia_pago_nominal': paymentDay ?? 7,
        'mes_pago': 'siguiente',
        'tipo_offset_pago': 'habiles',
      };
    case 'BANCOLOMBIA':
    case 'DAVIVIENDA':
    case 'BBVA':
    default:
      return {
        'banco_id': bank.id,
        'tipo_corte': 'fijo',
        'dia_corte_nominal': cutoffDay ?? 15,
        'tipo_pago': 'fijo',
        'dia_pago_nominal': paymentDay ?? 30,
        'mes_pago': 'siguiente',
        'tipo_offset_pago': 'calendario',
      };
  }
}

void main() {
  // -------------------------------------------------------------------------
  // Bank model tests
  // -------------------------------------------------------------------------
  group('Bank.fromJson', () {
    test('parses all fields correctly', () {
      final bank = Bank.fromJson({
        'id': 'uuid-1',
        'nombre': 'Bancolombia',
        'codigo': 'BANCOLOMBIA',
        'regla_ajuste_corte': 'adelantar_dia_habil_anterior',
        'regla_ajuste_pago': 'postergar_dia_habil_siguiente',
        'tipo_offset_default': 'calendario',
        'permite_cambio_fecha': false,
        'frecuencia_cambio_fecha': null,
        'logo_url': null,
        'activo': true,
      });

      expect(bank.id, 'uuid-1');
      expect(bank.name, 'Bancolombia');
      expect(bank.code, 'BANCOLOMBIA');
      expect(bank.adjustmentRuleCutoff, 'adelantar_dia_habil_anterior');
      expect(bank.adjustmentRulePayment, 'postergar_dia_habil_siguiente');
      expect(bank.isActive, true);
    });

    test('handles null optional fields without throwing', () {
      final bank = _bankFromCode('RAPPICARD', 'RappiCard');
      expect(bank.code, 'RAPPICARD');
      expect(bank.adjustmentRuleCutoff, isNull);
      expect(bank.logoUrl, isNull);
    });

    test('defaults isActive to true when missing', () {
      final bank = Bank.fromJson({
        'id': 'x',
        'nombre': 'Test',
        'codigo': 'TEST',
        // activo not present
      });
      expect(bank.isActive, true);
    });
  });

  // -------------------------------------------------------------------------
  // Credit card rules builder tests
  // -------------------------------------------------------------------------
  group('buildCreditCardRules', () {
    test('RappiCard → relative cutoff, 10 days after', () {
      final bank = _bankFromCode('RAPPICARD', 'RappiCard');
      final rules = buildCreditCardRules(bank: bank);

      expect(rules['tipo_corte'], 'relativo');
      expect(rules['corte_relativo_tipo'], 'penultimo_dia_habil');
      expect(rules['tipo_pago'], 'relativo_dias');
      expect(rules['dias_despues_corte'], 10);
      expect(rules['tipo_offset_pago'], 'calendario');
      // No nominal days for Rappi
      expect(rules.containsKey('dia_corte_nominal'), isFalse);
    });

    test('Nubank → fixed cutoff day 25, payment day 7 next month by default', () {
      final bank = _bankFromCode('NUBANK', 'Nubank');
      final rules = buildCreditCardRules(bank: bank);

      expect(rules['tipo_corte'], 'fijo');
      expect(rules['dia_corte_nominal'], 25);
      expect(rules['dia_pago_nominal'], 7);
      expect(rules['mes_pago'], 'siguiente');
      expect(rules['tipo_offset_pago'], 'habiles');
    });

    test('Nubank → custom cutoff/payment days respected', () {
      final bank = _bankFromCode('NUBANK', 'Nubank');
      final rules = buildCreditCardRules(bank: bank, cutoffDay: 20, paymentDay: 5);

      expect(rules['dia_corte_nominal'], 20);
      expect(rules['dia_pago_nominal'], 5);
    });

    test('Bancolombia → fixed cutoff day 15, payment day 30 by default', () {
      final bank = _bankFromCode('BANCOLOMBIA', 'Bancolombia');
      final rules = buildCreditCardRules(bank: bank);

      expect(rules['tipo_corte'], 'fijo');
      expect(rules['dia_corte_nominal'], 15);
      expect(rules['dia_pago_nominal'], 30);
      expect(rules['mes_pago'], 'siguiente');
      expect(rules['tipo_offset_pago'], 'calendario');
    });

    test('Davivienda → same defaults as Bancolombia', () {
      final bank = _bankFromCode('DAVIVIENDA', 'Davivienda');
      final rules = buildCreditCardRules(bank: bank);
      expect(rules['dia_corte_nominal'], 15);
      expect(rules['dia_pago_nominal'], 30);
    });

    test('BBVA → same defaults as Bancolombia', () {
      final bank = _bankFromCode('BBVA', 'BBVA');
      final rules = buildCreditCardRules(bank: bank);
      expect(rules['dia_corte_nominal'], 15);
      expect(rules['dia_pago_nominal'], 30);
    });

    test('Unknown bank → falls back to fixed 15/30 defaults', () {
      final bank = _bankFromCode('UNKNOWN_BANK', 'Mi Banco');
      final rules = buildCreditCardRules(bank: bank);
      expect(rules['tipo_corte'], 'fijo');
      expect(rules['dia_corte_nominal'], 15);
    });

    test('banco_id is always set correctly', () {
      for (final code in ['BANCOLOMBIA', 'NUBANK', 'RAPPICARD', 'DAVIVIENDA', 'BBVA']) {
        final bank = _bankFromCode(code, code);
        final rules = buildCreditCardRules(bank: bank);
        expect(rules['banco_id'], 'id-$code', reason: 'banco_id mismatch for $code');
      }
    });
  });

  // -------------------------------------------------------------------------
  // Edge cases
  // -------------------------------------------------------------------------
  group('Edge cases', () {
    test('cutoffDay=0 is passed through (boundary)', () {
      final bank = _bankFromCode('BANCOLOMBIA', 'Bancolombia');
      // Day 0 is invalid for the DB but the builder should not throw.
      final rules = buildCreditCardRules(bank: bank, cutoffDay: 0);
      expect(rules['dia_corte_nominal'], 0);
    });

    test('cutoffDay=31 is passed through (boundary)', () {
      final bank = _bankFromCode('BANCOLOMBIA', 'Bancolombia');
      final rules = buildCreditCardRules(bank: bank, cutoffDay: 31, paymentDay: 31);
      expect(rules['dia_corte_nominal'], 31);
      expect(rules['dia_pago_nominal'], 31);
    });

    test('negative payment day is not modified by builder', () {
      // Validation is the UI's job; builder is a pure data mapper.
      final bank = _bankFromCode('BANCOLOMBIA', 'Bancolombia');
      final rules = buildCreditCardRules(bank: bank, paymentDay: -1);
      expect(rules['dia_pago_nominal'], -1);
    });
  });

  // -------------------------------------------------------------------------
  // SharedPreferences: onboarding flag
  // -------------------------------------------------------------------------
  group('Onboarding SharedPreferences flag', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('flag is false by default', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_banks_completed'), isNull);
    });

    test('flag becomes true after marking completed', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_banks_completed', true);
      expect(prefs.getBool('onboarding_banks_completed'), isTrue);
    });

    test('flag can be reset', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_banks_completed', true);
      await prefs.remove('onboarding_banks_completed');
      expect(prefs.getBool('onboarding_banks_completed'), isNull);
    });

    test('different users/sessions do not bleed state (fresh mock each time)', () async {
      // Each setUp resets mock values, so this test confirms isolation.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_banks_completed'), isNull);
    });
  });
}
