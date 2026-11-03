import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/core/utils/card_recommendation.dart';
import 'package:budgett_frontend/core/utils/colombian_calendar.dart';
import 'package:budgett_frontend/core/utils/credit_card_calculator.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/bank_model.dart';
import 'package:budgett_frontend/data/models/credit_card_rules_model.dart';

Bank _bank(String id, {String? cutoffRule, String? paymentRule}) => Bank(
      id: id,
      name: id,
      code: id,
      adjustmentRuleCutoff: cutoffRule,
      adjustmentRulePayment: paymentRule,
    );

CreditCardRules _rules({
  required String accountId,
  required String bankId,
  required int cutDay,
  required int payDay,
  bool payNextMonth = false,
}) =>
    CreditCardRules(
      id: 'r-$accountId',
      accountId: accountId,
      bankId: bankId,
      cutoffType: CutoffType.fixed,
      nominalCutoffDay: cutDay,
      paymentType: PaymentType.fixed,
      nominalPaymentDay: payDay,
      paymentMonth: payNextMonth ? 'siguiente' : null,
    );

Account _card(String id, String name, CreditCardRules? rules) => Account(
      id: id,
      name: name,
      type: 'credit_card',
      balance: 0,
      creditCardRules: rules,
    );

void main() {
  // Plain bank: no business-day adjustment, so the dates are the nominal ones.
  final plain = _bank('plain');
  // Cut 15, pay 30 of the same month — the user's Bancolombia example.
  final bancolombiaRules =
      _rules(accountId: 'bc', bankId: 'plain', cutDay: 15, payDay: 30);

  group('CreditCardCalculator.scheduleForPurchase', () {
    test('a purchase on the cut-off day belongs to that cycle', () {
      final s = CreditCardCalculator.scheduleForPurchase(
          DateTime(2026, 10, 15), bancolombiaRules, plain);
      expect(s.cutoff, DateTime(2026, 10, 15));
      expect(s.payment, DateTime(2026, 10, 30));
      expect(
          CreditCardCalculator.daysBetween(DateTime(2026, 10, 15), s.payment),
          15);
    });

    test('the day after the cut-off rolls into the next cycle (~45 days)', () {
      final s = CreditCardCalculator.scheduleForPurchase(
          DateTime(2026, 10, 16), bancolombiaRules, plain);
      expect(s.cutoff, DateTime(2026, 11, 15));
      expect(s.payment, DateTime(2026, 11, 30));
      expect(
          CreditCardCalculator.daysBetween(DateTime(2026, 10, 16), s.payment),
          45);
    });

    test('time of day does not push a cut-off-day purchase to the next cycle',
        () {
      final s = CreditCardCalculator.scheduleForPurchase(
          DateTime(2026, 10, 15, 15, 30), bancolombiaRules, plain);
      expect(s.cutoff, DateTime(2026, 10, 15));
    });

    test('a cut-off on a holiday moves back, and so does the boundary', () {
      // 2026-11-11 (Cartagena) is moved by the Emiliani law to Monday 16th.
      expect(ColombianCalendar.isHoliday(DateTime(2026, 11, 16)), isTrue);
      // 2026-12-08 (Immaculate Conception) is a Tuesday holiday.
      expect(ColombianCalendar.isHoliday(DateTime(2026, 12, 8)), isTrue);

      final bank = _bank('adj',
          cutoffRule: 'adelantar_dia_habil_anterior',
          paymentRule: 'postergar_dia_habil_siguiente');
      final rules = _rules(
          accountId: 'x',
          bankId: 'adj',
          cutDay: 16,
          payDay: 8,
          payNextMonth: true);

      // Nominal cut-off Mon 16 is a holiday → Fri 13. Payment Tue Dec 8 is a
      // holiday → Wed Dec 9.
      final onCut = CreditCardCalculator.scheduleForPurchase(
          DateTime(2026, 11, 13), rules, bank);
      expect(onCut.cutoff, DateTime(2026, 11, 13));
      expect(onCut.payment, DateTime(2026, 12, 9));

      // Saturday 14th is already past the adjusted cut-off, although it is
      // before the nominal one.
      final dayAfter = CreditCardCalculator.scheduleForPurchase(
          DateTime(2026, 11, 14), rules, bank);
      expect(dayAfter.cutoff, DateTime(2026, 12, 16));
      expect(dayAfter.payment, DateTime(2027, 1, 8));
    });

    test('a payment date on a weekend is postponed by the bank rule', () {
      final bank = _bank('adj', paymentRule: 'postergar_dia_habil_siguiente');
      final rules =
          _rules(accountId: 'x', bankId: 'adj', cutDay: 15, payDay: 30);
      // Jan 30 2027 is a Saturday → Monday Feb 1.
      final s = CreditCardCalculator.scheduleForPurchase(
          DateTime(2026, 12, 16), rules, bank);
      expect(s.cutoff, DateTime(2027, 1, 15));
      expect(s.payment, DateTime(2027, 2, 1));
    });

    test('a billing-calendar override wins over the computed dates', () {
      final s = CreditCardCalculator.scheduleForPurchase(
        DateTime(2026, 10, 16),
        bancolombiaRules,
        plain,
        overrideFor: (y, m) => (y == 2026 && m == 10)
            ? (cutoff: DateTime(2026, 10, 20), payment: DateTime(2026, 11, 4))
            : null,
      );
      expect(s.cutoff, DateTime(2026, 10, 20));
      expect(s.payment, DateTime(2026, 11, 4));
    });
  });

  group('rankCardsForPurchase', () {
    final accounts = [
      _card('bc', 'Bancolombia', bancolombiaRules),
      // Cut 30, pay 15 of the next month.
      _card(
          'dv',
          'Davivienda',
          _rules(
              accountId: 'dv',
              bankId: 'plain',
              cutDay: 30,
              payDay: 15,
              payNextMonth: true)),
      _card('nr', 'No rules', null),
      _card('nb', 'Unknown bank',
          _rules(accountId: 'nb', bankId: 'missing', cutDay: 1, payDay: 20)),
      Account(id: 'sv', name: 'Savings', type: 'savings', balance: 0),
    ];

    test('the day after Bancolombia cuts, Bancolombia comes first', () {
      final ranked = rankCardsForPurchase(
        accounts: accounts,
        banks: [plain],
        purchaseDate: DateTime(2026, 10, 16),
      );
      expect(ranked.map((r) => r.account.id), ['bc', 'dv']);
      expect(ranked.first.daysToPay, 45);
      expect(ranked.last.daysToPay, 30); // Oct 30 cut → Nov 15
    });

    test('after the other card cuts, the order flips', () {
      final ranked = rankCardsForPurchase(
        accounts: accounts,
        banks: [plain],
        purchaseDate: DateTime(2026, 10, 31),
      );
      expect(ranked.map((r) => r.account.id), ['dv', 'bc']);
      expect(ranked.first.daysToPay, 45); // Nov 30 cut → Dec 15
      expect(ranked.last.daysToPay, 30); // Nov 15 cut → Nov 30
    });

    test('credit-card pockets are ranked too', () {
      final parent = Account(
        id: 'p',
        name: 'Parent',
        type: 'savings',
        balance: 0,
        pockets: [_card('pk', 'Pocket card', bancolombiaRules)],
      );
      final ranked = rankCardsForPurchase(
        accounts: [parent],
        banks: [plain],
        purchaseDate: DateTime(2026, 10, 16),
      );
      expect(ranked.single.account.id, 'pk');
    });
  });

  group('buildCardWidgetSnapshot', () {
    test('reports noCards when there is no credit card', () {
      final snap = buildCardWidgetSnapshot(
        accounts: [Account(id: 'sv', name: 'S', type: 'savings', balance: 0)],
        banks: [plain],
        from: DateTime(2026, 10, 16),
      );
      expect(snap['status'], 'noCards');
      expect(snap['days'], isEmpty);
    });

    test('reports noRules when no card has cut-off rules', () {
      final snap = buildCardWidgetSnapshot(
        accounts: [_card('nr', 'No rules', null)],
        banks: [plain],
        from: DateTime(2026, 10, 16),
      );
      expect(snap['status'], 'noRules');
      expect(snap['days'], isEmpty);
    });

    test('one entry per day, best card first, with rendered labels', () {
      final snap = buildCardWidgetSnapshot(
        accounts: [
          _card('bc', 'Bancolombia', bancolombiaRules),
          _card(
              'dv',
              'Davivienda',
              _rules(
                  accountId: 'dv',
                  bankId: 'plain',
                  cutDay: 30,
                  payDay: 15,
                  payNextMonth: true)),
        ],
        banks: [plain],
        from: DateTime(2026, 10, 15, 9, 41),
        days: 3,
        maxCards: 1,
      );
      expect(snap['status'], 'ok');
      final days = snap['days'] as List;
      expect(days.map((d) => d['date']),
          ['2026-10-15', '2026-10-16', '2026-10-17']);

      // On the cut-off day Bancolombia is due in 15 days, Davivienda in 31.
      final first = (days[0]['cards'] as List).single;
      expect(first['name'], 'Davivienda');
      expect(first['daysToPay'], 31);

      final second = (days[1]['cards'] as List).single;
      expect(second['name'], 'Bancolombia');
      expect(second['daysToPay'], 45);
      expect(second['due'], '2026-11-30');
      expect(second['dueLabel'], 'Due Mon, Nov 30');
    });
  });
}
