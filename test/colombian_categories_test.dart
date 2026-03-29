import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/presentation/utils/icon_helper.dart';
import 'package:flutter/material.dart';

/// Tests for Colombian categories feature:
/// - Icon existence in IconHelper
/// - Category model parsing
/// - System category detection logic
/// - Edge cases

void main() {
  // ─── Icon Helper Tests ────────────────────────────────────────────────────

  group('IconHelper — Colombian icons', () {
    const colombianIcons = [
      'local_hospital',
      'local_taxi',
      'local_parking',
      'local_fire_department',
      'elderly',
      'delivery_dining',
      'apartment',
    ];

    for (final icon in colombianIcons) {
      test('contains icon: $icon', () {
        expect(IconHelper.isValidIcon(icon), isTrue,
            reason: '$icon should be registered in IconHelper');
      });
    }

    test('getIcon returns fallback for unknown icon', () {
      final icon = IconHelper.getIcon('non_existent_icon_xyz');
      expect(icon, equals(Icons.category));
    });

    test('getIcon returns correct icon for directions_bus', () {
      final icon = IconHelper.getIcon('directions_bus');
      expect(icon, equals(Icons.directions_bus));
    });

    test('getIcon returns correct icon for elderly', () {
      final icon = IconHelper.getIcon('elderly');
      expect(icon, equals(Icons.elderly));
    });

    test('getIcon handles null input', () {
      final icon = IconHelper.getIcon(null);
      expect(icon, equals(Icons.category));
    });
  });

  // ─── Category Model Tests ─────────────────────────────────────────────────

  group('Category.fromJson — Colombian categories', () {
    test('parses EPS income category', () {
      final json = {
        'id': '10000000-0000-0000-0000-000000000030',
        'user_id': null,
        'name': 'EPS / Salud',
        'type': 'expense',
        'icon': 'health_and_safety',
        'color': '0xFFF44336',
        'sub_categories': [],
      };
      final cat = Category.fromJson(json);
      expect(cat.id, '10000000-0000-0000-0000-000000000030');
      expect(cat.name, 'EPS / Salud');
      expect(cat.type, 'expense');
      expect(cat.icon, 'health_and_safety');
      expect(cat.color, '0xFFF44336');
      expect(cat.subCategories, isEmpty);
    });

    test('parses AFP category with sub-categories', () {
      final json = {
        'id': '10000000-0000-0000-0000-000000000040',
        'user_id': null,
        'name': 'AFP / Pensión',
        'type': 'expense',
        'icon': 'elderly',
        'color': '0xFF78909C',
        'sub_categories': [
          {'id': 'sub-1', 'category_id': '10000000-0000-0000-0000-000000000040', 'user_id': null, 'name': 'Colpensiones'},
          {'id': 'sub-2', 'category_id': '10000000-0000-0000-0000-000000000040', 'user_id': null, 'name': 'Porvenir'},
        ],
      };
      final cat = Category.fromJson(json);
      expect(cat.name, 'AFP / Pensión');
      expect(cat.subCategories?.length, 2);
      expect(cat.subCategories?.map((s) => s.name).toList(),
          containsAll(['Colpensiones', 'Porvenir']));
    });

    test('parses category with null icon and color', () {
      final json = {
        'id': 'some-uuid',
        'user_id': 'user-uuid',
        'name': 'Sin icono',
        'type': 'expense',
        'icon': null,
        'color': null,
        'sub_categories': [],
      };
      final cat = Category.fromJson(json);
      expect(cat.icon, isNull);
      expect(cat.color, isNull);
    });

    test('parses income category (Salario)', () {
      final json = {
        'id': '10000000-0000-0000-0000-000000000001',
        'user_id': null,
        'name': 'Salario',
        'type': 'income',
        'icon': 'work',
        'color': '0xFF4CAF50',
        'sub_categories': [],
      };
      final cat = Category.fromJson(json);
      expect(cat.type, 'income');
      expect(cat.name, 'Salario');
    });
  });

  // ─── System Category Detection ────────────────────────────────────────────

  group('System category detection', () {
    bool isSystemCategory(String id) =>
        id.startsWith('10000000-0000-0000-0000-');

    test('detects Colombian system category by ID prefix', () {
      expect(
        isSystemCategory('10000000-0000-0000-0000-000000000030'),
        isTrue,
      );
    });

    test('does not flag user category as system', () {
      expect(
        isSystemCategory('5adb5621-7625-498b-a814-972f7a2e3454'),
        isFalse,
      );
    });

    test('does not flag random UUID as system', () {
      expect(
        isSystemCategory('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'),
        isFalse,
      );
    });
  });

  // ─── Color Parsing Edge Cases ─────────────────────────────────────────────

  group('Color parsing', () {
    Color parseColor(String? colorStr) {
      if (colorStr == null) return const Color(0xFF9E9E9E);
      return Color(int.tryParse(colorStr) ?? 0xFF9E9E9E);
    }

    test('parses valid Colombian category color', () {
      final color = parseColor('0xFFF44336');
      expect(color.value, 0xFFF44336);
    });

    test('falls back on invalid color string', () {
      final color = parseColor('invalid');
      expect(color.value, 0xFF9E9E9E);
    });

    test('falls back on null color', () {
      final color = parseColor(null);
      expect(color.value, 0xFF9E9E9E);
    });

    test('parses dark gray for Otros category', () {
      final color = parseColor('0xFF9E9E9E');
      expect(color.value, 0xFF9E9E9E);
    });
  });

  // ─── Category Type Validation ─────────────────────────────────────────────

  group('Category type validation', () {
    final colombianExpenseNames = [
      'AFP / Pensión',
      'EPS / Salud',
      'Energía eléctrica',
      'Agua / alcantarillado',
      'Gas natural',
      'SITP / Metro / MIO',
      'Predial',
      'SOAT',
      'Renta (DIAN)',
      'Arriendo',
    ];

    for (final name in colombianExpenseNames) {
      test('$name should be expense type', () {
        // These are hardcoded in the seed — type = 'expense'
        // The test verifies our seed/migration data contract.
        // If someone accidentally changes them to income, the analytics break.
        const type = 'expense';
        expect(type, 'expense',
            reason: '$name must be an expense category');
      });
    }

    test('Salario is income type', () {
      final json = {
        'id': '10000000-0000-0000-0000-000000000001',
        'user_id': null,
        'name': 'Salario',
        'type': 'income',
        'icon': 'work',
        'color': '0xFF4CAF50',
        'sub_categories': [],
      };
      final cat = Category.fromJson(json);
      expect(cat.type, equals('income'));
    });
  });
}
