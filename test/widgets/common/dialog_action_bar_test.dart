import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/presentation/widgets/common/dialog_action_bar.dart';

void main() {
  group('DialogActionBar', () {
    testWidgets('Save and Cancel buttons are present', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DialogActionBar(
              onSave: () {},
            ),
          ),
        ),
      );

      expect(find.text('Save Changes'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Delete button NOT present when onDelete is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DialogActionBar(
              onSave: () {},
              onDelete: null,
            ),
          ),
        ),
      );

      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('Delete button present when onDelete is provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DialogActionBar(
              onSave: () {},
              onDelete: () {},
            ),
          ),
        ),
      );

      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('buttons disabled when isLoading=true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DialogActionBar(
              onSave: () {},
              onDelete: () {},
              isLoading: true,
            ),
          ),
        ),
      );

      // Save button should show CircularProgressIndicator when loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // The FilledButton should be disabled (onPressed is null because isLoading)
      final filledButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(filledButton.onPressed, isNull);
    });
  });
}
