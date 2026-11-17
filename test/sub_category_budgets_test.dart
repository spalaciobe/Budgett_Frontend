import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/data/models/budget_model.dart';
import 'package:budgett_frontend/data/repositories/finance_repository.dart';

void main() {
  group('Budget.effectiveAmount', () {
    test('defaults to the sum of sub-category budgets', () {
      expect(Budget.effectiveAmount(null, {'a': 100, 'b': 50}), 150);
    });

    test('a larger category budget overrides the sum', () {
      expect(Budget.effectiveAmount(200, {'a': 100, 'b': 50}), 200);
    });

    test('a smaller category budget never undercuts the sub-categories', () {
      expect(Budget.effectiveAmount(120, {'a': 100, 'b': 50}), 150);
    });

    test('without sub-categories the category budget is used as-is', () {
      expect(Budget.effectiveAmount(80, const {}), 80);
      expect(Budget.effectiveAmount(null, const {}), 0);
    });
  });

  group('FinanceRepository.mergeBudgets', () {
    List<Budget> merge(List<Map<String, dynamic>> cats,
            List<Map<String, dynamic>> subs) =>
        FinanceRepository.mergeBudgets(
          categoryRows: cats,
          subCategoryRows: subs,
          month: 11,
          year: 2026,
        );

    test('category with only sub-category budgets gets a synthesized entry', () {
      final result = merge(const [], const [
        {'category_id': 'c1', 'sub_category_id': 's1', 'amount': 92000},
        {'category_id': 'c1', 'sub_category_id': 's2', 'amount': 100000},
      ]);
      expect(result, hasLength(1));
      final b = result.single;
      expect(b.id, '');
      expect(b.categoryAmount, isNull);
      expect(b.amount, 192000);
      expect(b.subCategoryBudgets, {'s1': 92000.0, 's2': 100000.0});
      expect(b.unassigned, 0);
    });

    test('explicit budget above the sum keeps the difference unassigned', () {
      final b = merge(const [
        {'id': 'b1', 'category_id': 'c1', 'amount': 350000, 'month': 11, 'year': 2026},
      ], const [
        {'category_id': 'c1', 'sub_category_id': 's1', 'amount': 92000},
        {'category_id': 'c1', 'sub_category_id': 's2', 'amount': 100000},
      ]).single;
      expect(b.id, 'b1');
      expect(b.categoryAmount, 350000);
      expect(b.amount, 350000);
      expect(b.unassigned, 158000);
    });

    test('sub-categories larger than the explicit budget win', () {
      final b = merge(const [
        {'id': 'b1', 'category_id': 'c1', 'amount': 200000, 'month': 11, 'year': 2026},
      ], const [
        {'category_id': 'c1', 'sub_category_id': 's1', 'amount': 150000},
        {'category_id': 'c1', 'sub_category_id': 's2', 'amount': 100000},
      ]).single;
      expect(b.amount, 250000);
      expect(b.unassigned, 0);
    });

    test('categories without sub-category budgets are unchanged', () {
      final result = merge(const [
        {'id': 'b1', 'category_id': 'c1', 'amount': 500000, 'month': 11, 'year': 2026},
        {'id': 'b2', 'category_id': 'c2', 'amount': 80000, 'month': 11, 'year': 2026},
      ], const []);
      final byCat = {for (final b in result) b.categoryId: b};
      expect(byCat['c1']!.amount, 500000);
      expect(byCat['c2']!.amount, 80000);
      expect(byCat['c2']!.subCategoryBudgets, isEmpty);
    });

    test('zero-amount sub-category rows are ignored', () {
      final result = merge(const [], const [
        {'category_id': 'c1', 'sub_category_id': 's1', 'amount': 0},
      ]);
      expect(result, isEmpty);
    });
  });
}
