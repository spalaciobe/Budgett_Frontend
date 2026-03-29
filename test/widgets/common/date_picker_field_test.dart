import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/presentation/widgets/common/date_picker_field.dart';

void main() {
  group('DatePickerField', () {
    testWidgets('shows "No date set" when selectedDate is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DatePickerField(
              selectedDate: null,
              label: 'Deadline',
              onDateSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('No date set'), findsOneWidget);
      expect(find.text('Deadline'), findsOneWidget);
    });

    testWidgets('shows formatted date when selectedDate is provided', (tester) async {
      final date = DateTime(2025, 6, 15);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DatePickerField(
              selectedDate: date,
              label: 'Date',
              onDateSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('2025-06-15'), findsOneWidget);
      expect(find.text('No date set'), findsNothing);
    });
  });
}
