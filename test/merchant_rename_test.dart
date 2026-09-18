import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budgett_frontend/data/models/merchant_alias_model.dart';
import 'package:budgett_frontend/data/repositories/message_capture_repository.dart';
import 'package:budgett_frontend/presentation/providers/message_capture_provider.dart';
import 'package:budgett_frontend/presentation/screens/capture_settings_screen.dart';

class _StubClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeRepository extends MessageCaptureRepository {
  _FakeRepository({this.recorded = 0}) : super(_StubClient());

  final int recorded;

  final List<({String id, Map<String, dynamic> data})> aliasUpdates = [];
  final List<({String from, String to})> renames = [];

  @override
  Future<int> countRecordedUnder(String name) async => recorded;

  @override
  Future<void> updateAlias(String id, Map<String, dynamic> data) async {
    aliasUpdates.add((id: id, data: data));
  }

  @override
  Future<int> renameRecordedMerchant({
    required String from,
    required String to,
  }) async {
    renames.add((from: from, to: to));
    return recorded;
  }
}

const _alias = MerchantAlias(
  id: 'alias-1',
  pattern: 'novaventa medellin c',
  displayName: 'Novaventa Medellin C',
  categoryId: 'cat-1',
  autoPost: true,
  hitCount: 4,
);

Widget _host(_FakeRepository repo) => ProviderScope(
      overrides: [
        messageCaptureRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(
        home: Scaffold(body: EditMerchantSheet(alias: _alias)),
      ),
    );

void main() {
  testWidgets('renaming a merchant offers to rename the movements it named',
      (tester) async {
    final repo = _FakeRepository(recorded: 3);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // Nothing to offer while the name is untouched: the checkbox would be
    // about a rename that isn't happening.
    expect(find.textContaining('Also rename'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Novaventa');
    await tester.pumpAndSettle();

    expect(find.text('Also rename the 3 movements already recorded'),
        findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.aliasUpdates.single.data['display_name'], 'Novaventa');
    expect(repo.renames.single.from, 'Novaventa Medellin C');
    expect(repo.renames.single.to, 'Novaventa');
  });

  testWidgets('declining leaves the recorded movements alone', (tester) async {
    final repo = _FakeRepository(recorded: 2);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Novaventa');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The rule is renamed either way — only the history is left as it was.
    expect(repo.aliasUpdates.single.data['display_name'], 'Novaventa');
    expect(repo.renames, isEmpty);
  });

  testWidgets('saving without renaming never touches the history',
      (tester) async {
    final repo = _FakeRepository(recorded: 5);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // Flip auto-post only.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.aliasUpdates.single.data['auto_post'], false);
    expect(repo.renames, isEmpty);
  });

  testWidgets('an empty name cannot be saved', (tester) async {
    final repo = _FakeRepository();
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pumpAndSettle();

    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
  });
}
