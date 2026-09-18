// End-to-end tests for the hybrid ingest behaviour, with in-memory fakes in
// place of Supabase and the platform channel.
//
// What these lock down is the promise of the feature: an unknown merchant is
// always reviewed once, a merchant that has been taught posts by itself, and
// the same payment arriving from two sources produces one expense.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:budgett_frontend/core/services/capture_ingest_service.dart';
import 'package:budgett_frontend/core/services/message_capture_service.dart';
import 'package:budgett_frontend/core/utils/capture_dedup.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/bank_model.dart';
import 'package:budgett_frontend/data/models/capture_source_model.dart';
import 'package:budgett_frontend/data/models/captured_message_model.dart';
import 'package:budgett_frontend/data/models/merchant_alias_model.dart';
import 'package:budgett_frontend/data/repositories/finance_repository.dart';
import 'package:budgett_frontend/data/repositories/message_capture_repository.dart';

// ─── fixtures ────────────────────────────────────────────────────────────────

final _receivedAt = DateTime(2026, 9, 17, 15, 44);

Account _account({
  String id = 'acc-savings',
  String name = 'Bancolombia Ahorro',
  String type = 'savings',
}) =>
    Account.fromJson({
      'id': id,
      'name': name,
      'type': type,
      'balance': 2000000,
    });

const _bancolombiaPurchase =
    'Bancolombia le informa Compra por \$45.900,00 en EXITO SUPER CL 80 '
    '17/09/2026 15:44. Tarjeta *1234';

RawCapture _capture({
  String channel = 'notification',
  String sourceKey = 'com.bancolombia.olimpia',
  String? sourceName = 'Bancolombia',
  String body = _bancolombiaPurchase,
  DateTime? receivedAt,
  double? latitude,
  double? longitude,
}) =>
    RawCapture(
      channel: channel,
      sourceKey: sourceKey,
      sourceName: sourceName,
      title: 'Bancolombia',
      body: body,
      receivedAt: receivedAt ?? _receivedAt,
      latitude: latitude,
      longitude: longitude,
    );

MerchantAlias _alias({
  String pattern = 'EXITO SUPER CL 80',
  String displayName = 'Éxito',
  String? categoryId = 'cat-food',
  String? accountId,
  bool autoPost = true,
}) =>
    MerchantAlias(
      id: 'alias-1',
      pattern: pattern,
      displayName: displayName,
      categoryId: categoryId,
      accountId: accountId,
      autoPost: autoPost,
    );

// ─── fakes ───────────────────────────────────────────────────────────────────

class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakePlatform implements CapturePlatform {
  final List<RawCapture> queue;
  final String? locationLabel;

  _FakePlatform(this.queue, {this.locationLabel});

  @override
  Future<List<RawCapture>> drain() async {
    final out = List<RawCapture>.from(queue);
    queue.clear();
    return out;
  }

  @override
  Future<String?> describeLocation(double latitude, double longitude) async =>
      locationLabel;
}

class _FakeCaptureRepository extends MessageCaptureRepository {
  _FakeCaptureRepository({
    this.aliases = const [],
    this.cardMappings = const {},
    this.sourceEnabled = true,
    this.existingFingerprints = const {},
    this.manualTransactions = const [],
  }) : super(_FakeSupabaseClient());

  List<MerchantAlias> aliases;
  Map<String, String> cardMappings;
  bool sourceEnabled;
  Set<String> existingFingerprints;
  List<DedupCandidate> manualTransactions;

  final List<CapturedMessage> inserted = [];
  final List<({String id, Map<String, dynamic> data})> updates = [];
  final List<String> touchedAliases = [];

  /// Latest state of each inserted row, after any updates.
  CapturedMessage? rowById(String id) {
    final base = inserted.where((m) => m.id == id).firstOrNull;
    if (base == null) return null;
    var json = _toJson(base);
    for (final update in updates.where((u) => u.id == id)) {
      json = {...json, ...update.data};
    }
    return CapturedMessage.fromJson(json);
  }

  Map<String, dynamic> _toJson(CapturedMessage m) => {
        'id': m.id,
        'source_id': m.sourceId,
        'channel': m.channel,
        'source_key': m.sourceKey,
        'title': m.title,
        'body': m.body,
        'received_at': m.receivedAt.toUtc().toIso8601String(),
        'occurred_at': m.occurredAt.toUtc().toIso8601String(),
        'latitude': m.latitude,
        'longitude': m.longitude,
        'location_label': m.locationLabel,
        'parse_status': m.parseStatus,
        'issuer_key': m.issuerKey,
        'merchant_raw': m.merchantRaw,
        'merchant_display': m.merchantDisplay,
        'amount': m.amount,
        'currency': m.currency,
        'card_last4': m.cardLast4,
        'kind': m.kind?.wireName,
        'confidence': m.confidence,
        'matched_alias_id': m.matchedAliasId,
        'status': m.status,
        'transaction_id': m.transactionId,
        'duplicate_of': m.duplicateOf,
        'dedup_hash': m.dedupHashValue,
        'fingerprint': m.fingerprint,
        'error': m.error,
      };

  @override
  Future<Set<String>> knownFingerprints({int lookbackDays = 7}) async =>
      Set<String>.from(existingFingerprints);

  @override
  Future<List<MerchantAlias>> getAliases() async => aliases;

  @override
  Future<Map<String, String>> getCardMappings() async => cardMappings;

  @override
  Future<CaptureSource> registerSource({
    required String channel,
    required String sourceKey,
    String? detectedName,
    String? issuerKey,
    DateTime? seenAt,
  }) async =>
      CaptureSource(
        id: 'src-$channel-$sourceKey',
        channel: channel,
        sourceKey: sourceKey,
        detectedName: detectedName,
        isEnabled: sourceEnabled,
      );

  @override
  Future<CapturedMessage> insertCapture(Map<String, dynamic> data) async {
    final message = CapturedMessage.fromJson({
      ...data,
      'id': 'cap-${inserted.length + 1}',
    });
    inserted.add(message);
    return message;
  }

  @override
  Future<void> updateCapture(String id, Map<String, dynamic> data) async {
    updates.add((id: id, data: data));
  }

  @override
  Future<List<CapturedMessage>> capturesNear(DateTime around,
          {Duration span = const Duration(hours: 6)}) async =>
      inserted
          .where((m) => m.status == 'pending' || m.status == 'posted')
          .toList();

  @override
  Future<List<DedupCandidate>> transactionsNear({
    required DateTime day,
    required double amount,
    required String currency,
  }) async =>
      manualTransactions;

  @override
  Future<void> touchAlias(String id, int currentHitCount) async {
    touchedAliases.add(id);
  }
}

class _FakeFinanceRepository extends FinanceRepository {
  _FakeFinanceRepository() : super(_FakeSupabaseClient());

  final List<Map<String, dynamic>> posted = [];

  @override
  Future<String> addTransactionWithReturn(
      Map<String, dynamic> transactionData) async {
    posted.add(transactionData);
    return 'tx-${posted.length}';
  }
}

// ─── harness ─────────────────────────────────────────────────────────────────

Future<
    ({
      CaptureIngestResult result,
      _FakeCaptureRepository captures,
      _FakeFinanceRepository finance,
    })> _ingest(
  List<RawCapture> queue, {
  List<MerchantAlias> aliases = const [],
  Map<String, String> cardMappings = const {},
  bool sourceEnabled = true,
  Set<String> existingFingerprints = const {},
  List<DedupCandidate> manualTransactions = const [],
  String? locationLabel,
  CaptureSettings settings = const CaptureSettings(),
  List<Account>? accounts,
}) async {
  final captures = _FakeCaptureRepository(
    aliases: aliases,
    cardMappings: cardMappings,
    sourceEnabled: sourceEnabled,
    existingFingerprints: existingFingerprints,
    manualTransactions: manualTransactions,
  );
  final finance = _FakeFinanceRepository();

  final service = CaptureIngestService(
    captureRepo: captures,
    financeRepo: finance,
    platform: _FakePlatform(List.of(queue), locationLabel: locationLabel),
  );

  final result = await service.ingest(
    accounts: accounts ?? [_account()],
    banks: const <Bank>[],
    settings: settings,
  );

  return (result: result, captures: captures, finance: finance);
}

void main() {
  group('first sighting of a merchant', () {
    test('goes to the inbox instead of being guessed at', () async {
      final run = await _ingest([_capture()]);

      expect(run.result.inserted, 1);
      expect(run.result.pending, 1);
      expect(run.result.posted, 0);
      // Nothing is recorded until the user has confirmed the merchant once.
      expect(run.finance.posted, isEmpty);

      final row = run.captures.inserted.single;
      expect(row.status, 'pending');
      expect(row.amount, 45900.0);
      expect(row.merchantRaw, 'EXITO SUPER CL 80');
      // A friendly name is suggested up front so the inbox reads well.
      // Short all-caps tokens keep their case (CL, SAS, ATM).
      expect(row.merchantDisplay, 'Exito Super CL 80');
      expect(row.cardLast4, '1234');
    });
  });

  group('a taught merchant', () {
    test('posts by itself, with time and place', () async {
      final run = await _ingest(
        [_capture(latitude: 4.6851, longitude: -74.0546)],
        aliases: [_alias(accountId: 'acc-savings')],
        locationLabel: 'Calle 80 #45-12, Bogotá',
      );

      expect(run.result.posted, 1);
      expect(run.result.pending, 0);

      final tx = run.finance.posted.single;
      expect(tx['amount'], 45900.0);
      expect(tx['type'], 'expense');
      expect(tx['status'], 'paid');
      expect(tx['description'], 'Éxito');
      expect(tx['place'], 'Éxito');
      expect(tx['category_id'], 'cat-food');
      expect(tx['account_id'], 'acc-savings');
      expect(tx['auto_captured'], isTrue);
      // The accounting day and the exact instant of the payment.
      expect(tx['date'], '2026-09-17');
      expect(tx['occurred_at'],
          DateTime(2026, 9, 17, 15, 44).toUtc().toIso8601String());
      // Where it happened, captured natively when the message arrived.
      expect(tx['latitude'], 4.6851);
      expect(tx['longitude'], -74.0546);
      expect(tx['location_label'], 'Calle 80 #45-12, Bogotá');
      expect(tx['captured_message_id'], 'cap-1');

      // The capture is linked back to the transaction it produced.
      expect(run.captures.rowById('cap-1')!.status, 'posted');
      expect(run.captures.rowById('cap-1')!.transactionId, 'tx-1');
      expect(run.captures.touchedAliases, ['alias-1']);
    });

    test('still waits when the alias has no category', () async {
      final run = await _ingest(
        [_capture()],
        aliases: [_alias(categoryId: null, accountId: 'acc-savings')],
      );
      expect(run.result.pending, 1);
      expect(run.finance.posted, isEmpty);
    });

    test('still waits when auto-posting was switched off for it', () async {
      final run = await _ingest(
        [_capture()],
        aliases: [_alias(accountId: 'acc-savings', autoPost: false)],
      );
      expect(run.result.pending, 1);
    });

    test('still waits when no account can be resolved', () async {
      // Alias has no account, no card mapping, no source default.
      final run = await _ingest([_capture()], aliases: [_alias()]);
      expect(run.result.pending, 1);
      expect(run.finance.posted, isEmpty);
    });

    test('resolves the account from the learned card mapping', () async {
      final run = await _ingest(
        [_capture()],
        aliases: [_alias()],
        cardMappings: {'bancolombia|1234': 'acc-savings'},
      );
      expect(run.result.posted, 1);
      expect(run.finance.posted.single['account_id'], 'acc-savings');
    });

    test('respects the always-review amount cap', () async {
      final run = await _ingest(
        [_capture()],
        aliases: [_alias(accountId: 'acc-savings')],
        settings: const CaptureSettings(autoPostMaxAmount: 20000),
      );
      expect(run.result.pending, 1);
      expect(run.finance.posted, isEmpty);
    });

    test('respects the global automation switch', () async {
      final run = await _ingest(
        [_capture()],
        aliases: [_alias(accountId: 'acc-savings')],
        settings: const CaptureSettings(autoPostEnabled: false),
      );
      expect(run.result.pending, 1);
    });
  });

  group('the same payment from two sources', () {
    test('records one expense and files the copy as a duplicate', () async {
      // Bancolombia pushes a notification and sends an SMS three minutes apart.
      final run = await _ingest(
        [
          _capture(),
          _capture(
            channel: 'sms',
            sourceKey: '890255',
            sourceName: '890255',
            receivedAt: _receivedAt.add(const Duration(minutes: 3)),
          ),
        ],
        aliases: [_alias(accountId: 'acc-savings')],
      );

      expect(run.result.inserted, 2);
      expect(run.result.posted, 1);
      expect(run.result.duplicates, 1);
      // One expense, not two.
      expect(run.finance.posted, hasLength(1));

      final duplicate =
          run.captures.inserted.firstWhere((m) => m.channel == 'sms');
      expect(duplicate.status, 'duplicate');
      expect(duplicate.duplicateOf, 'cap-1');
    });

    test('two genuinely different purchases both go through', () async {
      final run = await _ingest(
        [
          _capture(),
          _capture(
            body: 'Bancolombia le informa Compra por \$12.000 en JUAN VALDEZ '
                '17/09/2026 15:50. Tarjeta *1234',
            receivedAt: _receivedAt.add(const Duration(minutes: 6)),
          ),
        ],
        aliases: [_alias(accountId: 'acc-savings')],
      );

      expect(run.result.duplicates, 0);
      expect(run.result.inserted, 2);
      // Only the taught merchant posts; the new one waits for review.
      expect(run.result.posted, 1);
      expect(run.result.pending, 1);
    });

    test('a capture already ingested is skipped on the next drain', () async {
      final capture = _capture();
      final run = await _ingest(
        [capture],
        existingFingerprints: {capture.fingerprint},
      );
      expect(run.result.inserted, 0);
      expect(run.captures.inserted, isEmpty);
    });
  });

  group('messages that must not become expenses', () {
    test('a disabled source is dropped before anything is stored', () async {
      final run = await _ingest([_capture()], sourceEnabled: false);

      expect(run.result.inserted, 0);
      expect(run.result.skippedDisabledSource, 1);
      expect(run.captures.inserted, isEmpty);
    });

    test('a one-time password is stored as dismissed, never posted', () async {
      final run = await _ingest([
        _capture(
            body: 'Bancolombia: Tu clave dinamica es 123456, '
                'compra por \$50.000'),
      ]);

      expect(run.result.ignored, 1);
      expect(run.captures.inserted.single.status, 'dismissed');
      expect(run.finance.posted, isEmpty);
    });

    test('a declined purchase is recorded but moves no money', () async {
      final run = await _ingest(
        [
          _capture(
              body: 'Bancolombia: Compra por \$45.900 en EXITO SUPER CL 80 '
                  'rechazada'),
        ],
        aliases: [_alias(accountId: 'acc-savings')],
      );

      expect(run.result.ignored, 1);
      expect(run.captures.inserted.single.status, 'dismissed');
      expect(run.finance.posted, isEmpty);
    });

    test('an unreadable message is kept for manual entry', () async {
      final run = await _ingest([
        _capture(body: 'Bancolombia: movimiento registrado en tu cuenta'),
      ]);

      expect(run.result.pending, 1);
      expect(run.captures.inserted.single.parseStatus, 'unparsed');
    });
  });

  group('collision with a manual entry', () {
    test('blocks auto-posting and explains why', () async {
      // The user already typed this expense before the message arrived.
      final manual = DedupCandidate(
        id: 'tx-manual',
        amount: 45900,
        occurredAt: DateTime(2026, 9, 17),
        dayPrecisionOnly: true,
      );

      final run = await _ingest(
        [_capture()],
        aliases: [_alias(accountId: 'acc-savings')],
        manualTransactions: [manual],
      );

      expect(run.result.posted, 0);
      expect(run.result.pending, 1);
      expect(run.finance.posted, isEmpty);
      expect(run.captures.inserted.single.error, isNotNull);
    });
  });

  group('capture fingerprint', () {
    test('is stable for the same capture', () {
      expect(_capture().fingerprint, _capture().fingerprint);
    });

    test('separates different bodies from the same source and instant', () {
      final a = _capture(body: 'Compra por \$10.000 en TIENDA A');
      final b = _capture(body: 'Compra por \$10.000 en TIENDA B');
      expect(a.fingerprint, isNot(b.fingerprint));
    });

    test('separates the two channels reporting the same payment', () {
      expect(_capture().fingerprint,
          isNot(_capture(channel: 'sms', sourceKey: '890255').fingerprint));
    });

    test('holds no value beyond 2^53, so it compiles and matches on the web', () {
      // A 64-bit hash is a dart2js compile error ("can't be represented
      // exactly in JavaScript") and would also diverge between the VM and the
      // browser. Every component here must stay web-safe.
      final parts = _capture().fingerprint.split('|');
      expect(parts, hasLength(5));
      final hash = int.parse(parts.last, radix: 16);
      expect(hash, lessThan(0x80000000));
      expect(int.parse(parts[2]), lessThan(9007199254740992)); // 2^53
    });
  });

  group('result summary', () {
    test('reads as a single line for the sync snackbar', () async {
      final run = await _ingest(
        [
          _capture(),
          _capture(
            body: 'Bancolombia le informa Compra por \$12.000 en JUAN VALDEZ '
                '17/09/2026 15:50. Tarjeta *1234',
            receivedAt: _receivedAt.add(const Duration(minutes: 6)),
          ),
        ],
        aliases: [_alias(accountId: 'acc-savings')],
      );

      expect(run.result.summary, '1 recorded · 1 to review');
    });

    test('an empty queue says so', () async {
      final run = await _ingest(const []);
      expect(run.result.summary, 'No new messages');
      expect(run.result.isEmpty, isTrue);
    });
  });
}
