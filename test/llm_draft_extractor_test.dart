// The model is a backup with the last word on nothing. These lock that down,
// including the messy answers a four-bit 2B model actually returns.

import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/core/parsing/expense_draft.dart';
import 'package:budgett_frontend/core/parsing/llm_draft_extractor.dart';
import 'package:budgett_frontend/core/parsing/message_kind.dart';
import 'package:budgett_frontend/core/services/local_llm_service.dart';

/// Returns a canned answer, so the behaviour under test is ours, not a
/// model's.
class _FakeLlm implements LocalLlmService {
  _FakeLlm(this.answer, {this.unavailable = false});

  final String answer;
  final bool unavailable;
  int calls = 0;

  @override
  Future<String> generate(String prompt) async {
    calls++;
    if (unavailable) throw const LocalLlmUnavailable('no model');
    return answer;
  }

  @override
  bool get isSupported => true;
  @override
  Future<bool> isInstalled() async => !unavailable;
  @override
  Future<int> installedSize() async => 0;
  @override
  Future<void> remove() async {}
  @override
  Future<void> download(LocalModelOption option,
          {DownloadProgress? onProgress, Object? client}) async =>
      throw UnimplementedError();
}

ExpenseDraft _unsure({double? amount, String? merchant}) => ExpenseDraft(
      source: DraftSource.receipt,
      amount: amount,
      merchant: merchant,
      date: DateTime(2026, 10, 6),
      confidence: 0.3,
      rawText: 'BLURRY RECEIPT 45900',
    );

void main() {
  group('reading the answer', () {
    test('reads a clean object', () {
      final read = parseModelAnswer(
        '{"amount":45900,"currency":"COP","merchant":"LA LLAMITA",'
        '"date":"2026-10-05","direction":"out"}',
      )!;
      expect(read.amount, 45900);
      expect(read.currency, 'COP');
      expect(read.merchant, 'LA LLAMITA');
      expect(read.date, DateTime(2026, 10, 5));
      expect(read.moneyOut, isTrue);
    });

    test('digs the object out of the prose around it', () {
      final read = parseModelAnswer(
        'Sure! Here is the JSON you asked for:\n'
        '```json\n{"amount":12000,"currency":"COP","merchant":null,'
        '"date":null,"direction":"out"}\n```\n'
        'Let me know if you need anything else.',
      )!;
      expect(read.amount, 12000);
      expect(read.merchant, isNull);
    });

    test('takes the first object when the model keeps talking', () {
      final read = parseModelAnswer(
        '{"amount":5000,"direction":"out"} {"amount":9999}',
      )!;
      expect(read.amount, 5000);
    });

    test('survives a brace inside a string', () {
      final read = parseModelAnswer(
        r'{"merchant":"CAFE {EL ROBLE}","amount":8000}',
      )!;
      expect(read.merchant, 'CAFE {EL ROBLE}');
      expect(read.amount, 8000);
    });

    test('reads a separated number the model was told not to send', () {
      expect(parseModelAnswer('{"amount":"45.900"}')!.amount, 45900);
      expect(parseModelAnswer('{"amount":"\$ 2.500,50"}')!.amount, 2500.50);
    });

    test('rejects nonsense instead of inventing a figure', () {
      expect(parseModelAnswer('I could not read the image'), isNull);
      expect(parseModelAnswer(''), isNull);
      // An object the model never closed is not partially trusted.
      expect(parseModelAnswer('{broken'), isNull);
      expect(parseModelAnswer('{"amount":4'), isNull);
    });

    test('drops an amount of zero or less', () {
      expect(parseModelAnswer('{"amount":0}')!.amount, isNull);
      expect(parseModelAnswer('{"amount":-500}')!.amount, isNull);
    });

    test('drops a merchant that is really a sentence', () {
      final read = parseModelAnswer(
        '{"merchant":"I am not able to determine the merchant from this '
        'image because the text is unclear"}',
      )!;
      expect(read.merchant, isNull);
    });
  });

  group('what it is allowed to change', () {
    test('fills an amount the rules could not read', () async {
      final llm = _FakeLlm('{"amount":45900,"currency":"COP"}');
      final result = await completeWithModel(_unsure(), llm: llm);

      expect(result.amount, 45900);
      expect(llm.calls, 1);
    });

    test('never overwrites an amount the rules did read', () async {
      // A figure off a line that said "TOTAL A PAGAR" beats anything a 2B
      // model infers.
      final llm = _FakeLlm('{"amount":99999,"merchant":"OTRA COSA"}');
      final result =
          await completeWithModel(_unsure(amount: 45900), llm: llm);

      expect(result.amount, 45900);
    });

    test('never overwrites a merchant the rules did read', () async {
      final llm = _FakeLlm('{"amount":45900,"merchant":"WRONG"}');
      final result = await completeWithModel(
        _unsure(merchant: 'LA LLAMITA S.A.S.'),
        llm: llm,
      );
      expect(result.merchant, 'LA LLAMITA S.A.S.');
    });

    test('a rescued draft still asks to be checked', () async {
      final llm = _FakeLlm('{"amount":45900}');
      final result = await completeWithModel(_unsure(), llm: llm);

      expect(result.confidence, lessThan(kDraftReviewThreshold));
      expect(result.warning, contains('on-device model'));
    });

    test('does not run at all on a draft the rules are sure of', () async {
      final llm = _FakeLlm('{"amount":99999}');
      final sure = ExpenseDraft(
        source: DraftSource.receipt,
        amount: 45900,
        merchant: 'LA LLAMITA',
        date: DateTime(2026, 10, 5),
        confidence: 0.95,
        rawText: 'TOTAL A PAGAR 45.900',
      );

      final result = await completeWithModel(sure, llm: llm);
      expect(llm.calls, 0);
      expect(result.amount, 45900);
    });

    test('no model installed leaves the draft exactly as it was', () async {
      final llm = _FakeLlm('', unavailable: true);
      final draft = _unsure();
      final result = await completeWithModel(draft, llm: llm);

      expect(result.amount, isNull);
      expect(result.warning, draft.warning);
      expect(result.confidence, draft.confidence);
    });

    test('an answer with nothing in it changes nothing', () async {
      final llm = _FakeLlm('{"amount":null,"merchant":null}');
      final result = await completeWithModel(_unsure(), llm: llm);

      expect(result.amount, isNull);
      expect(result.warning, isNot(contains('on-device')));
    });

    test('a direction of "in" only applies when it supplied the amount',
        () async {
      final llm = _FakeLlm('{"amount":720000,"direction":"in"}');
      final result = await completeWithModel(_unsure(), llm: llm);
      expect(result.kind, MessageKind.transferIn);
    });
  });

  group('the prompt', () {
    test('carries the text and asks for JSON only', () {
      final prompt = buildExtractionPrompt('TOTAL A PAGAR 45.900');
      expect(prompt, contains('TOTAL A PAGAR 45.900'));
      expect(prompt, contains('JSON only'));
      expect(prompt, contains('"amount":45900'));
    });

    test('shows an empty answer as well as a full one', () {
      // With only a complete example the model copies that shape and fills
      // every field, inventing an amount for text that has none.
      final prompt = buildExtractionPrompt('anything');
      expect(prompt, contains('"amount":null'));
    });

    test('states the separator rule', () {
      // Trained mostly on English, the model reads 45.900 as 45.9.
      expect(buildExtractionPrompt('x'), contains('45.900 means 45900'));
    });

    test('says which figure on a receipt is the one', () {
      final prompt = buildExtractionPrompt('x');
      for (final trap in ['subtotal', 'cash handed over', 'change']) {
        expect(prompt, contains(trap));
      }
    });

    test('forbids inventing a number', () {
      expect(buildExtractionPrompt('x'), contains('Never invent'));
    });

    test('names the shape it is reading', () {
      expect(
        buildExtractionPrompt('x', source: DraftSource.voice),
        contains('someone spoke'),
      );
      expect(
        buildExtractionPrompt('x', source: DraftSource.receipt),
        contains('receipt or a bank app screen'),
      );
    });

    test('stays short enough to be worth running on a phone', () {
      // Every token of prompt is a second of spinner. Roughly four
      // characters per token puts this near 300, against a 256-token answer.
      expect(buildExtractionPrompt('short text').length, lessThan(1400));
    });
  });
}
