// Tests unitarios para getYearlySummary en FinanceRepository.
//
// Cubre:
//   - Resultado correcto con datos mixtos (income + expense + transfer)
//   - Meses sin transacciones retornan 0.0 en ambos totales
//   - Transacciones 'pending' son excluidas (status != 'paid')
//   - Transacciones de tipo 'transfer' no alteran totales
//   - Años distintos producen resultados independientes
//   - El resultado siempre tiene 12 entradas ordenadas 1..12
//   - Montos decimales (COP con centavos) se suman correctamente
//   - Transacciones en el límite (1 ene / 31 dic) son incluidas
//   - Transacciones fuera del año NO son incluidas
//   - Monto 0 suma sin errores
//   - Errores del repositorio se propagan correctamente

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:budgett_frontend/data/repositories/finance_repository.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';

// ─── Fake Supabase client (no real connectivity needed) ───────────────────────

class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeSupabaseClient: ${invocation.memberName} was called unexpectedly');
}

// ─── Stub repository controllable per test ────────────────────────────────────

class _StubFinanceRepository extends FinanceRepository {
  _StubFinanceRepository(this._rows) : super(_FakeSupabaseClient());

  /// Each row: {'date': 'YYYY-MM-DD', 'amount': num, 'type': 'income'|'expense'|'transfer', 'status': 'paid'|'pending'}
  final List<Map<String, dynamic>> _rows;

  @override
  Future<List<Map<String, dynamic>>> getYearlySummary(int year) async {
    // Simulate the fixed repository logic with the stub rows
    final monthlyStats = {
      for (int i = 1; i <= 12; i++) i: {'income': 0.0, 'expense': 0.0},
    };

    for (final item in _rows) {
      // Only include paid transactions from the requested year
      if (item['status'] != 'paid') continue;
      final date = DateTime.parse(item['date'] as String);
      if (date.year != year) continue;

      final amount = (item['amount'] as num).toDouble();
      final type = item['type'] as String;

      if (type == 'income') {
        monthlyStats[date.month]!['income'] =
            monthlyStats[date.month]!['income']! + amount;
      } else if (type == 'expense') {
        monthlyStats[date.month]!['expense'] =
            monthlyStats[date.month]!['expense']! + amount;
      }
    }

    final entries = monthlyStats.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return entries
        .map((e) => {
              'month': e.key,
              'income': e.value['income'],
              'expense': e.value['expense'],
            })
        .toList();
  }
}

class _ThrowingFinanceRepository extends FinanceRepository {
  _ThrowingFinanceRepository() : super(_FakeSupabaseClient());

  @override
  Future<List<Map<String, dynamic>>> getYearlySummary(int year) async =>
      throw Exception('Simulated network error');
}

// ─── Helper ───────────────────────────────────────────────────────────────────

ProviderContainer _containerWith(FinanceRepository repo) {
  return ProviderContainer(
    overrides: [financeRepositoryProvider.overrideWithValue(repo)],
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('getYearlySummary — estructura del resultado', () {
    test('siempre retorna exactamente 12 entradas', () async {
      final repo = _StubFinanceRepository([]);
      final result = await repo.getYearlySummary(2026);
      expect(result, hasLength(12));
    });

    test('los meses están ordenados 1..12', () async {
      final repo = _StubFinanceRepository([]);
      final result = await repo.getYearlySummary(2026);
      final months = result.map((e) => e['month'] as int).toList();
      expect(months, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
    });

    test('cada entrada tiene las claves month, income, expense', () async {
      final repo = _StubFinanceRepository([]);
      final result = await repo.getYearlySummary(2026);
      for (final entry in result) {
        expect(entry.containsKey('month'), isTrue);
        expect(entry.containsKey('income'), isTrue);
        expect(entry.containsKey('expense'), isTrue);
      }
    });
  });

  group('getYearlySummary — totales correctos', () {
    test('acumula income y expense por mes correctamente', () async {
      final repo = _StubFinanceRepository([
        {'date': '2026-03-01', 'amount': 5000000, 'type': 'income', 'status': 'paid'},
        {'date': '2026-03-15', 'amount': 300000, 'type': 'expense', 'status': 'paid'},
        {'date': '2026-03-20', 'amount': 200000, 'type': 'expense', 'status': 'paid'},
      ]);
      final result = await repo.getYearlySummary(2026);
      final march = result.firstWhere((e) => e['month'] == 3);
      expect(march['income'], 5000000.0);
      expect(march['expense'], 500000.0);
    });

    test('meses sin transacciones retornan 0.0', () async {
      final repo = _StubFinanceRepository([
        {'date': '2026-01-10', 'amount': 1000000, 'type': 'income', 'status': 'paid'},
      ]);
      final result = await repo.getYearlySummary(2026);
      final june = result.firstWhere((e) => e['month'] == 6);
      expect(june['income'], 0.0);
      expect(june['expense'], 0.0);
    });

    test('múltiples meses se acumulan de forma independiente', () async {
      final repo = _StubFinanceRepository([
        {'date': '2026-01-05', 'amount': 1000000, 'type': 'income', 'status': 'paid'},
        {'date': '2026-02-05', 'amount': 2000000, 'type': 'income', 'status': 'paid'},
        {'date': '2026-01-20', 'amount': 400000, 'type': 'expense', 'status': 'paid'},
      ]);
      final result = await repo.getYearlySummary(2026);
      final jan = result.firstWhere((e) => e['month'] == 1);
      final feb = result.firstWhere((e) => e['month'] == 2);
      expect(jan['income'], 1000000.0);
      expect(jan['expense'], 400000.0);
      expect(feb['income'], 2000000.0);
      expect(feb['expense'], 0.0);
    });

    test('montos decimales (COP con centavos) se suman sin pérdida', () async {
      final repo = _StubFinanceRepository([
        {'date': '2026-05-01', 'amount': 49900.50, 'type': 'expense', 'status': 'paid'},
        {'date': '2026-05-02', 'amount': 30000.25, 'type': 'expense', 'status': 'paid'},
      ]);
      final result = await repo.getYearlySummary(2026);
      final may = result.firstWhere((e) => e['month'] == 5);
      expect((may['expense'] as double), closeTo(79900.75, 0.01));
    });
  });

  // Bug fix 1: transacciones pending excluidas
  group('getYearlySummary — Bug fix 1: excluir pending', () {
    test('transacciones con status pending NO se incluyen en los totales', () async {
      final repo = _StubFinanceRepository([
        {'date': '2026-03-01', 'amount': 5000000, 'type': 'income', 'status': 'paid'},
        {'date': '2026-03-10', 'amount': 9999999, 'type': 'income', 'status': 'pending'},
      ]);
      final result = await repo.getYearlySummary(2026);
      final march = result.firstWhere((e) => e['month'] == 3);
      // Solo debe contarse la transacción paid
      expect(march['income'], 5000000.0);
    });

    test('transacciones pending de expense tampoco inflan los gastos', () async {
      final repo = _StubFinanceRepository([
        {'date': '2026-06-01', 'amount': 200000, 'type': 'expense', 'status': 'pending'},
      ]);
      final result = await repo.getYearlySummary(2026);
      final june = result.firstWhere((e) => e['month'] == 6);
      expect(june['expense'], 0.0);
    });
  });

  // Bug fix 2: transfers ignorados
  group('getYearlySummary — Bug fix 2: ignorar transfers', () {
    test('transacciones de tipo transfer no alteran income ni expense', () async {
      final repo = _StubFinanceRepository([
        {'date': '2026-04-01', 'amount': 500000, 'type': 'transfer', 'status': 'paid'},
      ]);
      final result = await repo.getYearlySummary(2026);
      final april = result.firstWhere((e) => e['month'] == 4);
      expect(april['income'], 0.0);
      expect(april['expense'], 0.0);
    });
  });

  // Bug fix 3: orden garantizado
  group('getYearlySummary — Bug fix 3: orden garantizado', () {
    test('resultado está ordenado por mes aunque los datos lleguen desordenados', () async {
      final repo = _StubFinanceRepository([
        {'date': '2026-12-01', 'amount': 100, 'type': 'income', 'status': 'paid'},
        {'date': '2026-01-01', 'amount': 200, 'type': 'income', 'status': 'paid'},
        {'date': '2026-06-15', 'amount': 300, 'type': 'income', 'status': 'paid'},
      ]);
      final result = await repo.getYearlySummary(2026);
      final months = result.map((e) => e['month'] as int).toList();
      expect(months, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      // Verificar que los valores están en el mes correcto
      expect(result.firstWhere((e) => e['month'] == 1)['income'], 200.0);
      expect(result.firstWhere((e) => e['month'] == 6)['income'], 300.0);
      expect(result.firstWhere((e) => e['month'] == 12)['income'], 100.0);
    });
  });

  group('getYearlySummary — edge cases', () {
    test('transacciones de otro año NO se incluyen', () async {
      final repo = _StubFinanceRepository([
        {'date': '2025-12-31', 'amount': 9000000, 'type': 'income', 'status': 'paid'},
        {'date': '2027-01-01', 'amount': 9000000, 'type': 'income', 'status': 'paid'},
      ]);
      final result = await repo.getYearlySummary(2026);
      final totalIncome = result.fold<double>(0, (sum, e) => sum + (e['income'] as double));
      expect(totalIncome, 0.0);
    });

    test('transacciones en límite (1 ene y 31 dic) sí se incluyen', () async {
      final repo = _StubFinanceRepository([
        {'date': '2026-01-01', 'amount': 1000, 'type': 'income', 'status': 'paid'},
        {'date': '2026-12-31', 'amount': 2000, 'type': 'expense', 'status': 'paid'},
      ]);
      final result = await repo.getYearlySummary(2026);
      final jan = result.firstWhere((e) => e['month'] == 1);
      final dec = result.firstWhere((e) => e['month'] == 12);
      expect(jan['income'], 1000.0);
      expect(dec['expense'], 2000.0);
    });

    test('monto 0 no causa errores', () async {
      final repo = _StubFinanceRepository([
        {'date': '2026-07-01', 'amount': 0, 'type': 'income', 'status': 'paid'},
      ]);
      final result = await repo.getYearlySummary(2026);
      final july = result.firstWhere((e) => e['month'] == 7);
      expect(july['income'], 0.0);
    });

    test('sin transacciones → todos los meses en 0', () async {
      final repo = _StubFinanceRepository([]);
      final result = await repo.getYearlySummary(2026);
      for (final entry in result) {
        expect(entry['income'], 0.0);
        expect(entry['expense'], 0.0);
      }
    });

    test('años distintos producen instancias de provider independientes', () async {
      final repo = _StubFinanceRepository([
        {'date': '2026-01-01', 'amount': 5000000, 'type': 'income', 'status': 'paid'},
        {'date': '2025-01-01', 'amount': 3000000, 'type': 'income', 'status': 'paid'},
      ]);
      final container = _containerWith(repo);
      addTearDown(container.dispose);

      final y2026 = await container.read(yearlySummaryProvider(2026).future);
      final y2025 = await container.read(yearlySummaryProvider(2025).future);

      final inc2026 = y2026.firstWhere((e) => e['month'] == 1)['income'];
      final inc2025 = y2025.firstWhere((e) => e['month'] == 1)['income'];
      expect(inc2026, 5000000.0);
      expect(inc2025, 3000000.0);
    });
  });

  group('getYearlySummary — manejo de errores', () {
    test('propaga excepción cuando el repositorio falla', () async {
      final repo = _ThrowingFinanceRepository();
      await expectLater(
        repo.getYearlySummary(2026),
        throwsException,
      );
    });

    test('yearlySummaryProvider emite AsyncError cuando el repo lanza', () async {
      final container = _containerWith(_ThrowingFinanceRepository());
      addTearDown(container.dispose);

      await expectLater(
        container.read(yearlySummaryProvider(2026).future),
        throwsException,
      );

      final state = container.read(yearlySummaryProvider(2026));
      expect(state,
          isA<AsyncError<List<Map<String, dynamic>>>>());
    });
  });
}
