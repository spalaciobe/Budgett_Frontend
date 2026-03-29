import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/presentation/widgets/common/dialog_header.dart';

void main() {
  group('DialogHeader', () {
    testWidgets('renders the title text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DialogHeader(title: 'Test Title'),
          ),
        ),
      );

      expect(find.text('Test Title'), findsOneWidget);
    });

    testWidgets('tapping close button calls Navigator.pop', (tester) async {
      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        body: PopScope(
                          canPop: true,
                          onPopInvokedWithResult: (didPop, _) {
                            if (didPop) popped = true;
                          },
                          child: const DialogHeader(title: 'Close Me'),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      // Navigate to the page with DialogHeader
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Close Me'), findsOneWidget);

      // Tap close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(popped, isTrue);
    });
  });
}
