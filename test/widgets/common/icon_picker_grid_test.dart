import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/presentation/widgets/common/icon_picker_grid.dart';

void main() {
  group('IconPickerGrid', () {
    testWidgets('renders without throwing for valid icon list', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IconPickerGrid(
              iconOptions: const ['home', 'flag', 'savings'],
              selectedIcon: 'home',
              onIconSelected: (_) {},
            ),
          ),
        ),
      );

      // Should render 3 icon containers
      expect(find.byType(InkWell), findsNWidgets(3));
    });

    testWidgets('selected icon has primary color border', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: const ColorScheme.light(primary: Colors.blue)),
          home: Scaffold(
            body: IconPickerGrid(
              iconOptions: const ['home', 'flag'],
              selectedIcon: 'home',
              onIconSelected: (_) {},
            ),
          ),
        ),
      );

      // Find all Container widgets with BoxDecoration
      final containers = tester.widgetList<Container>(find.byType(Container)).where((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration && decoration.border is Border) {
          final border = decoration.border as Border;
          return border.top.width == 2;
        }
        return false;
      });

      // The selected icon should have a border with width 2
      expect(containers.length, 1);
    });
  });
}
