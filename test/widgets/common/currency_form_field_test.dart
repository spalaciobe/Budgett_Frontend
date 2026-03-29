import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/presentation/widgets/common/currency_form_field.dart';

void main() {
  group('CurrencyFormField', () {
    Widget buildTestWidget({
      TextEditingController? controller,
      String labelText = 'Amount',
      bool required = true,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Form(
            autovalidateMode: AutovalidateMode.always,
            child: CurrencyFormField(
              controller: controller ?? TextEditingController(),
              labelText: labelText,
              required: required,
            ),
          ),
        ),
      );
    }

    testWidgets('shows labelText', (tester) async {
      await tester.pumpWidget(buildTestWidget(labelText: 'Budget Amount'));
      expect(find.text('Budget Amount'), findsOneWidget);
    });

    testWidgets('validator returns error for empty when required=true', (tester) async {
      final controller = TextEditingController(text: '');
      await tester.pumpWidget(buildTestWidget(controller: controller, required: true));
      await tester.pump();

      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('validator returns null for valid amount', (tester) async {
      final controller = TextEditingController(text: '1.000');
      await tester.pumpWidget(buildTestWidget(controller: controller));
      await tester.pump();

      expect(find.text('Required'), findsNothing);
      expect(find.text('Invalid number'), findsNothing);
    });

    testWidgets('validator passes when required=false and field is empty', (tester) async {
      final controller = TextEditingController(text: '');
      await tester.pumpWidget(buildTestWidget(controller: controller, required: false));
      await tester.pump();

      expect(find.text('Required'), findsNothing);
      expect(find.text('Invalid number'), findsNothing);
    });
  });
}
