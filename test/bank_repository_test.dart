// Tests for BankRepository and bankRepositoryProvider
// Strategy: subclass BankRepository with a FakeBankRepository that overrides
// getBanks() returning in-memory data — no Supabase connectivity needed.
// Also covers BankRepository error propagation and provider wiring.

// ignore_for_file: subtype_of_sealed_class

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:budgett_frontend/data/repositories/bank_repository.dart';
import 'package:budgett_frontend/data/models/bank_model.dart';

// ─── Fake Supabase client ─────────────────────────────────────────────────────

class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeSupabaseClient: ${invocation.memberName} should never be called');
}

// ─── Fake repository (happy path) ────────────────────────────────────────────

class _FakeBankRepository extends BankRepository {
  final List<Bank> _banks;

  _FakeBankRepository(this._banks) : super(_FakeSupabaseClient());

  @override
  Future<List<Bank>> getBanks() async => _banks;
}

// ─── Fake repository (error path) ────────────────────────────────────────────

class _ThrowingBankRepository extends BankRepository {
  final Exception _error;

  _ThrowingBankRepository(this._error) : super(_FakeSupabaseClient());

  @override
  Future<List<Bank>> getBanks() async => throw _error;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Bank _nubank() => Bank.fromJson({
      'id': 'bank-nubank',
      'nombre': 'Nubank',
      'codigo': 'NUBANK',
      'regla_ajuste_corte': null,
      'regla_ajuste_pago': null,
      'tipo_offset_default': 'calendario',
      'permite_cambio_fecha': false,
      'frecuencia_cambio_fecha': null,
      'logo_url': 'https://cdn.example.com/nubank.png',
      'activo': true,
    });

Bank _bancolombia() => Bank.fromJson({
      'id': 'bank-bancolombia',
      'nombre': 'Bancolombia',
      'codigo': 'BANCOLOMBIA',
      'regla_ajuste_corte': 'siguiente_dia_habil',
      'regla_ajuste_pago': 'siguiente_dia_habil',
      'tipo_offset_default': 'calendario',
      'permite_cambio_fecha': true,
      'frecuencia_cambio_fecha': 'anual',
      'logo_url': null,
      'activo': true,
    });

Bank _inactivoBank() => Bank.fromJson({
      'id': 'bank-old',
      'nombre': 'Banco Obsoleto',
      'codigo': 'OLD',
      'regla_ajuste_corte': null,
      'regla_ajuste_pago': null,
      'tipo_offset_default': 'calendario',
      'permite_cambio_fecha': false,
      'frecuencia_cambio_fecha': null,
      'logo_url': null,
      'activo': false,
    });

// ─── BankRepository tests ─────────────────────────────────────────────────────

void main() {
  // ─── Bank.fromJson ──────────────────────────────────────────────────────────

  group('Bank.fromJson', () {
    test('parses all fields correctly', () {
      final b = _bancolombia();
      expect(b.id, 'bank-bancolombia');
      expect(b.name, 'Bancolombia');
      expect(b.code, 'BANCOLOMBIA');
      expect(b.adjustmentRuleCutoff, 'siguiente_dia_habil');
      expect(b.adjustmentRulePayment, 'siguiente_dia_habil');
      expect(b.defaultOffsetType, 'calendario');
      expect(b.allowsDateChange, true);
      expect(b.dateChangeFrequency, 'anual');
      expect(b.isActive, true);
    });

    test('null optional fields do not throw', () {
      final b = _nubank();
      expect(b.adjustmentRuleCutoff, isNull);
      expect(b.adjustmentRulePayment, isNull);
      expect(b.dateChangeFrequency, isNull);
      expect(b.logoUrl, isNotNull); // nubank has URL
    });

    test('defaults isActive to true when missing', () {
      final b = Bank.fromJson({
        'id': 'x',
        'nombre': 'X',
        'codigo': 'XX',
        // activo omitted
      });
      expect(b.isActive, true);
    });

    test('defaults defaultOffsetType to calendario when missing', () {
      final b = Bank.fromJson({
        'id': 'x',
        'nombre': 'X',
        'codigo': 'XX',
        // tipo_offset_default omitted
      });
      expect(b.defaultOffsetType, 'calendario');
    });

    test('defaults allowsDateChange to false when missing', () {
      final b = Bank.fromJson({
        'id': 'x',
        'nombre': 'X',
        'codigo': 'XX',
        // permite_cambio_fecha omitted
      });
      expect(b.allowsDateChange, false);
    });

    test('inactive bank parses isActive false', () {
      final b = _inactivoBank();
      expect(b.isActive, false);
    });

    test('logoUrl null is allowed', () {
      final b = _bancolombia();
      expect(b.logoUrl, isNull);
    });

    test('logoUrl populated is returned correctly', () {
      final b = _nubank();
      expect(b.logoUrl, 'https://cdn.example.com/nubank.png');
    });

    test('edge case: empty code string is accepted', () {
      final b = Bank.fromJson({
        'id': 'b',
        'nombre': 'Sin código',
        'codigo': '',
      });
      expect(b.code, '');
    });

    test('edge case: all adjustment rules set', () {
      final b = Bank.fromJson({
        'id': 'b',
        'nombre': 'Full Rules',
        'codigo': 'FULL',
        'regla_ajuste_corte': 'siguiente_dia_habil',
        'regla_ajuste_pago': 'mismo_dia_habil',
        'tipo_offset_default': 'habil',
        'permite_cambio_fecha': true,
        'frecuencia_cambio_fecha': 'mensual',
      });
      expect(b.adjustmentRuleCutoff, 'siguiente_dia_habil');
      expect(b.adjustmentRulePayment, 'mismo_dia_habil');
      expect(b.defaultOffsetType, 'habil');
      expect(b.allowsDateChange, true);
      expect(b.dateChangeFrequency, 'mensual');
    });
  });

  // ─── BankRepository.getBanks ────────────────────────────────────────────────

  group('BankRepository.getBanks', () {
    test('returns empty list when no banks exist', () async {
      final repo = _FakeBankRepository([]);
      final banks = await repo.getBanks();
      expect(banks, isEmpty);
    });

    test('returns single bank correctly', () async {
      final repo = _FakeBankRepository([_nubank()]);
      final banks = await repo.getBanks();
      expect(banks, hasLength(1));
      expect(banks.first.name, 'Nubank');
    });

    test('returns multiple banks', () async {
      final repo = _FakeBankRepository([_nubank(), _bancolombia()]);
      final banks = await repo.getBanks();
      expect(banks, hasLength(2));
      expect(banks.map((b) => b.code), containsAll(['NUBANK', 'BANCOLOMBIA']));
    });

    test('returns inactive banks (filtering is caller responsibility)', () async {
      final repo = _FakeBankRepository([_nubank(), _inactivoBank()]);
      final banks = await repo.getBanks();
      expect(banks, hasLength(2));
      expect(banks.any((b) => !b.isActive), isTrue);
    });

    test('propagates exception when Supabase fails', () async {
      final error = Exception('Supabase connection error');
      final repo = _ThrowingBankRepository(error);
      expect(() => repo.getBanks(), throwsException);
    });

    test('propagates specific error message', () async {
      final repo = _ThrowingBankRepository(
        Exception('JWT expired'),
      );
      expect(
        () => repo.getBanks(),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('JWT expired'),
        )),
      );
    });
  });

  // ─── bankRepositoryProvider ─────────────────────────────────────────────────

  group('bankRepositoryProvider', () {
    test('can be overridden with a fake in ProviderContainer', () {
      final fake = _FakeBankRepository([_nubank()]);
      final container = ProviderContainer(
        overrides: [
          bankRepositoryProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(bankRepositoryProvider);
      expect(repo, isA<BankRepository>());
    });

    test('overridden provider returns same fake instance', () {
      final fake = _FakeBankRepository([_nubank()]);
      final container = ProviderContainer(
        overrides: [
          bankRepositoryProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(bankRepositoryProvider), same(fake));
    });
  });

  // ─── banksFutureProvider ─────────────────────────────────────────────────────

  group('banksFutureProvider', () {
    test('resolves with banks from repository', () async {
      final fake = _FakeBankRepository([_nubank(), _bancolombia()]);
      final container = ProviderContainer(
        overrides: [
          bankRepositoryProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(banksFutureProvider.future);
      expect(result, hasLength(2));
      expect(result.first.name, 'Nubank');
    });

    test('resolves with empty list when no banks', () async {
      final fake = _FakeBankRepository([]);
      final container = ProviderContainer(
        overrides: [
          bankRepositoryProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(banksFutureProvider.future);
      expect(result, isEmpty);
    });

    test('becomes AsyncData after resolution', () async {
      final fake = _FakeBankRepository([_nubank()]);
      final container = ProviderContainer(
        overrides: [
          bankRepositoryProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      await container.read(banksFutureProvider.future);
      expect(container.read(banksFutureProvider), isA<AsyncData<List<Bank>>>());
    });

    test('emits AsyncError when repository throws', () async {
      final throwing = _ThrowingBankRepository(
        Exception('Failed to fetch banks'),
      );
      final container = ProviderContainer(
        overrides: [
          bankRepositoryProvider.overrideWithValue(throwing),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(banksFutureProvider.future),
        throwsException,
      );

      final state = container.read(banksFutureProvider);
      expect(state, isA<AsyncError<List<Bank>>>());
    });

    test('results can be filtered by isActive after resolution', () async {
      final fake = _FakeBankRepository([
        _nubank(),
        _bancolombia(),
        _inactivoBank(),
      ]);
      final container = ProviderContainer(
        overrides: [
          bankRepositoryProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final allBanks = await container.read(banksFutureProvider.future);
      final activeBanks = allBanks.where((b) => b.isActive).toList();

      expect(allBanks, hasLength(3));
      expect(activeBanks, hasLength(2));
    });

    test('Colombian banks have correct codes', () async {
      final fake = _FakeBankRepository([_nubank(), _bancolombia()]);
      final container = ProviderContainer(
        overrides: [
          bankRepositoryProvider.overrideWithValue(fake),
        ],
      );
      addTearDown(container.dispose);

      final banks = await container.read(banksFutureProvider.future);
      final codes = banks.map((b) => b.code).toSet();
      expect(codes, containsAll(['NUBANK', 'BANCOLOMBIA']));
    });
  });

  // ─── Edge cases: Bank model ───────────────────────────────────────────────

  group('Bank model edge cases', () {
    test('two banks with same code are distinct by ID', () {
      final b1 = Bank.fromJson({
        'id': 'id-1',
        'nombre': 'Banco A',
        'codigo': 'SAME',
      });
      final b2 = Bank.fromJson({
        'id': 'id-2',
        'nombre': 'Banco B',
        'codigo': 'SAME',
      });
      expect(b1.id, isNot(b2.id));
      expect(b1.code, b2.code);
    });

    test('bank with Unicode name parses correctly', () {
      final b = Bank.fromJson({
        'id': 'b-unicode',
        'nombre': 'Banco de Bogotá S.A.',
        'codigo': 'BBOGOTA',
      });
      expect(b.name, 'Banco de Bogotá S.A.');
    });

    test('repository preserves insertion order of banks', () async {
      final banks = [_bancolombia(), _nubank(), _inactivoBank()];
      final repo = _FakeBankRepository(banks);
      final result = await repo.getBanks();
      expect(result[0].code, 'BANCOLOMBIA');
      expect(result[1].code, 'NUBANK');
      expect(result[2].code, 'OLD');
    });
  });
}
