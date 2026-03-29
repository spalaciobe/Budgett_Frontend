import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/presentation/widgets/common/color_picker_row.dart';

void main() {
  group('ColorPickerRow', () {
    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColorPickerRow(
              colorOptions: const ['0xFF4CAF50', '0xFF2196F3', '0xFFF44336'],
              selectedColor: '0xFF4CAF50',
              onColorSelected: (_) {},
            ),
          ),
        ),
      );

      // Should render 3 color circles
      expect(find.byType(GestureDetector), findsNWidgets(3));
    });

    testWidgets('selected color shows check icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColorPickerRow(
              colorOptions: const ['0xFF4CAF50', '0xFF2196F3'],
              selectedColor: '0xFF4CAF50',
              onColorSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });
}
