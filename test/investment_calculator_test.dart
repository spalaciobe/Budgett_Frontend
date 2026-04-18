import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/core/utils/investment_calculator.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/investment_details_model.dart';
import 'package:budgett_frontend/data/models/investment_holding_model.dart';
import 'package:budgett_frontend/data/models/fx_rate_model.dart';
import 'package:budgett_frontend/data/models/savings_interest_details_model.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

InvestmentHolding _holding({
  String id = 'h1',
  String symbol = 'BTC',
  String currency = 'COP',
  double quantity = 1.0,
  double avgCost = 100.0,
  double currentPrice = 120.0,
}) =>
    InvestmentHolding(
      id: id,
      userId: 'u1',
      accountId: 'a1',
      symbol: symbol,
      assetClass: 'crypto',
      currency: currency,
      quantity: quantity,
      avgCost: avgCost,
      currentPrice: currentPrice,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

Account _account({
  String type = 'investment',
  double balance = 0.0,
  double balanceUsd = 0.0,
  InvestmentDetails? investmentDetails,
}) =>
    Account(
      id: 'a1',
      name: 'Test Account',
      type: type,
      balance: balance,
      balanceUsd: balanceUsd,
      investmentDetails: investmentDetails,
    );

InvestmentDetails _cdtDetails({
  double principal = 1000000.0,
  double interestRate = 0.11, // 11% E.A.
  int termDays = 180,
  DateTime? startDate,
  DateTime? maturityDate,
}) {
  final start = startDate ?? DateTime(2026, 1, 1);
  final maturity = maturityDate ?? start.add(Duration(days: termDays));
  return InvestmentDetails(
    id: 'd1',
    accountId: 'a1',
    investmentType: InvestmentType.cdt,
    principal: principal,
    interestRate: interestRate,
    termDays: termDays,
    startDate: start,
    maturityDate: maturity,
  );
}

FxRate _fxRate(double rate) => FxRate(
      id: 'fx1',
      base: 'USD',
      quote: 'COP',
      rate: rate,
      asOfDate: DateTime(2026, 4, 12),
      source: 'test',
      fetchedAt: DateTime(2026, 4, 12),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── InvestmentHolding computed properties ───────────────────────────────────

  group('InvestmentHolding computed properties', () {
    test('marketValue = quantity × currentPrice', () {
      final h = _holding(quantity: 2.0, currentPrice: 300.0);
      expect(h.marketValue, closeTo(600.0, 0.001));
    });

    test('costBasis = quantity × avgCost', () {
      final h = _holding(quantity: 2.0, avgCost: 250.0);
      expect(h.costBasis, closeTo(500.0, 0.001));
    });

    test('unrealizedPnl = marketValue − costBasis', () {
      final h = _holding(quantity: 1.0, avgCost: 100.0, currentPrice: 120.0);
      expect(h.unrealizedPnl, closeTo(20.0, 0.001));
    });

    test('unrealizedPnl is negative when price fell', () {
      final h = _holding(quantity: 1.0, avgCost: 100.0, currentPrice: 80.0);
      expect(h.unrealizedPnl, closeTo(-20.0, 0.001));
    });

    test('unrealizedPnlPct = (pnl / costBasis) × 100', () {
      final h = _holding(quantity: 1.0, avgCost: 100.0, currentPrice: 120.0);
      expect(h.unrealizedPnlPct, closeTo(20.0, 0.001));
    });

    test('unrealizedPnlPct is 0 when costBasis is 0', () {
      final h = _holding(quantity: 0.0, avgCost: 0.0, currentPrice: 120.0);
      expect(h.unrealizedPnlPct, 0.0);
    });
  });

  // ── computePnl ──────────────────────────────────────────────────────────────

  group('InvestmentCalculator.computePnl', () {
    test('empty list returns all zeros', () {
      final pnl = InvestmentCalculator.computePnl([]);
      expect(pnl.costBasis, 0.0);
      expect(pnl.marketValue, 0.0);
      expect(pnl.pnl, 0.0);
      expect(pnl.pnlPct, 0.0);
    });

    test('single holding', () {
      final h = _holding(quantity: 10.0, avgCost: 100.0, currentPrice: 130.0);
      final pnl = InvestmentCalculator.computePnl([h]);
      expect(pnl.costBasis, closeTo(1000.0, 0.001));
      expect(pnl.marketValue, closeTo(1300.0, 0.001));
      expect(pnl.pnl, closeTo(300.0, 0.001));
      expect(pnl.pnlPct, closeTo(30.0, 0.001));
    });

    test('multiple holdings aggregated', () {
      final h1 = _holding(
          id: 'h1', quantity: 10.0, avgCost: 100.0, currentPrice: 110.0);
      final h2 = _holding(
          id: 'h2', quantity: 5.0, avgCost: 200.0, currentPrice: 180.0);
      final pnl = InvestmentCalculator.computePnl([h1, h2]);
      // costBasis = 1000 + 1000 = 2000
      // marketValue = 1100 + 900 = 2000
      expect(pnl.costBasis, closeTo(2000.0, 0.001));
      expect(pnl.marketValue, closeTo(2000.0, 0.001));
      expect(pnl.pnl, closeTo(0.0, 0.001));
      expect(pnl.pnlPct, closeTo(0.0, 0.001));
    });

    test('pnlPct is 0 when costBasis is 0 (no division by zero)', () {
      final h = _holding(quantity: 0.0, avgCost: 0.0, currentPrice: 100.0);
      final pnl = InvestmentCalculator.computePnl([h]);
      expect(pnl.pnlPct, 0.0);
    });
  });

  // ── CDT helpers ─────────────────────────────────────────────────────────────

  group('InvestmentCalculator CDT helpers', () {
    test('projectCdtValue at start date equals principal', () {
      final details = _cdtDetails(
        principal: 1000000.0,
        interestRate: 0.11,
        startDate: DateTime(2026, 1, 1),
      );
      final value =
          InvestmentCalculator.projectCdtValue(details, DateTime(2026, 1, 1));
      expect(value, closeTo(1000000.0, 0.01));
    });

    test('projectCdtValue after 365 days equals principal × (1 + rate)', () {
      final start = DateTime(2026, 1, 1);
      final details = _cdtDetails(
        principal: 1000000.0,
        interestRate: 0.11,
        termDays: 365,
        startDate: start,
        maturityDate: start.add(const Duration(days: 365)),
      );
      final value = InvestmentCalculator.projectCdtValue(
          details, start.add(const Duration(days: 365)));
      expect(value, closeTo(1110000.0, 1.0)); // 1M × 1.11
    });

    test('projectCdtValue returns principal when required fields are null', () {
      final details = InvestmentDetails(
        id: 'd1',
        accountId: 'a1',
        investmentType: InvestmentType.cdt,
        principal: 500000.0,
      );
      expect(
          InvestmentCalculator.projectCdtValue(details, DateTime.now()),
          500000.0);
    });

    test('projectCdtMaturityValue uses maturity date', () {
      final start = DateTime(2026, 1, 1);
      final maturity = start.add(const Duration(days: 180));
      final details = _cdtDetails(
        principal: 1000000.0,
        interestRate: 0.11,
        termDays: 180,
        startDate: start,
        maturityDate: maturity,
      );
      final atMaturity =
          InvestmentCalculator.projectCdtMaturityValue(details);
      final expected = 1000000.0 * (1 + 0.11 * 180 / 365);
      expect(atMaturity, closeTo(expected, 1.0));
    });

    test('cdtDaysToMaturity returns positive days for future maturity', () {
      final future = DateTime.now().add(const Duration(days: 30));
      final details = _cdtDetails(maturityDate: future);
      final days = InvestmentCalculator.cdtDaysToMaturity(details);
      // Allow ±1 for clock differences during test execution
      expect(days, inInclusiveRange(29, 31));
    });

    test('cdtDaysToMaturity returns 0 for past maturity date', () {
      final past = DateTime.now().subtract(const Duration(days: 10));
      final details = _cdtDetails(maturityDate: past);
      expect(InvestmentCalculator.cdtDaysToMaturity(details), 0);
    });

    test('cdtDaysToMaturity returns 0 when maturityDate is null', () {
      final details = InvestmentDetails(
        id: 'd1',
        accountId: 'a1',
        investmentType: InvestmentType.cdt,
      );
      expect(InvestmentCalculator.cdtDaysToMaturity(details), 0);
    });

    test('isCdtMatured is true for past maturity date', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final details = _cdtDetails(maturityDate: past);
      expect(InvestmentCalculator.isCdtMatured(details), isTrue);
    });

    test('isCdtMatured is false for future maturity date', () {
      final future = DateTime.now().add(const Duration(days: 30));
      final details = _cdtDetails(maturityDate: future);
      expect(InvestmentCalculator.isCdtMatured(details), isFalse);
    });

    test('isCdtMatured is false when maturityDate is null', () {
      final details = InvestmentDetails(
        id: 'd1',
        accountId: 'a1',
        investmentType: InvestmentType.cdt,
      );
      expect(InvestmentCalculator.isCdtMatured(details), isFalse);
    });

    test('cdtAccruedInterest is positive after some days have passed', () {
      final start = DateTime.now().subtract(const Duration(days: 90));
      final maturity = start.add(const Duration(days: 180));
      final details = _cdtDetails(
        principal: 1000000.0,
        interestRate: 0.11,
        termDays: 180,
        startDate: start,
        maturityDate: maturity,
      );
      final interest = InvestmentCalculator.cdtAccruedInterest(details);
      expect(interest, greaterThan(0));
    });
  });

  // ── High-yield helpers ───────────────────────────────────────────────────────

  group('InvestmentCalculator high-yield helpers', () {
    test('projectedAnnualIncome = balance × apy', () {
      expect(
        InvestmentCalculator.projectedAnnualIncome(1000000.0, 0.0925),
        closeTo(92500.0, 0.01),
      );
    });

    test('projectedMonthlyIncome = annualIncome / 12', () {
      expect(
        InvestmentCalculator.projectedMonthlyIncome(1200000.0, 0.09),
        closeTo(9000.0, 0.01),
      );
    });

    test('projectedAnnualIncome with zero APY returns 0', () {
      expect(InvestmentCalculator.projectedAnnualIncome(1000000.0, 0.0), 0.0);
    });

    test('savingsDailyIncome uses E.A. compound daily rate', () {
      // dailyRate = (1 + 0.0925)^(1/365) - 1 ≈ 0.000242...
      // dailyIncome = 1_000_000 × dailyRate ≈ 242.xx
      final income =
          InvestmentCalculator.savingsDailyIncome(1000000.0, 0.0925);
      expect(income, closeTo(242.0, 2.0)); // within ±2 COP tolerance
    });

    test('savingsDailyIncome returns 0 for zero balance', () {
      expect(InvestmentCalculator.savingsDailyIncome(0.0, 0.0925), 0.0);
    });

    test('savingsDailyIncome returns 0 for zero APY', () {
      expect(InvestmentCalculator.savingsDailyIncome(1000000.0, 0.0), 0.0);
    });

    test('savingsAccruedInterest for 30 days at 9.25% E.A.', () {
      // interest = 1_000_000 × ((1.0925)^(30/365) - 1)
      // ≈ 1_000_000 × 0.007268 ≈ 7268
      final fromDate = DateTime.now().subtract(const Duration(days: 30));
      final interest = InvestmentCalculator.savingsAccruedInterest(
          1000000.0, 0.0925, fromDate);
      expect(interest, closeTo(7268.0, 50.0)); // ±50 COP tolerance
    });

    test('savingsAccruedInterest returns 0 when fromDate is today', () {
      final today = DateTime.now();
      final interest =
          InvestmentCalculator.savingsAccruedInterest(1000000.0, 0.0925, today);
      expect(interest, 0.0);
    });

    test('savingsAccruedInterest returns 0 for future fromDate', () {
      final future = DateTime.now().add(const Duration(days: 5));
      final interest =
          InvestmentCalculator.savingsAccruedInterest(1000000.0, 0.0925, future);
      expect(interest, 0.0);
    });

    test('savingsAccruedInterest is greater for longer periods', () {
      final from30 = DateTime.now().subtract(const Duration(days: 30));
      final from60 = DateTime.now().subtract(const Duration(days: 60));
      final interest30 = InvestmentCalculator.savingsAccruedInterest(
          1000000.0, 0.0925, from30);
      final interest60 = InvestmentCalculator.savingsAccruedInterest(
          1000000.0, 0.0925, from60);
      expect(interest60, greaterThan(interest30));
    });
  });

  // ── savingsAccruedInterestWithSegments ─────────────────────────────────────

  group('InvestmentCalculator.savingsAccruedInterestWithSegments', () {
    test('empty segments falls back to single-segment result', () {
      final fromDate = DateTime.now().subtract(const Duration(days: 30));
      final withSegments =
          InvestmentCalculator.savingsAccruedInterestWithSegments(
        segments: const [],
        currentBalance: 1000000.0,
        currentApyRate: 0.0925,
        lastInterestDate: fromDate,
      );
      final legacy = InvestmentCalculator.savingsAccruedInterest(
          1000000.0, 0.0925, fromDate);
      expect(withSegments, closeTo(legacy, 0.001));
    });

    test('single segment with no balance change equals single-segment result', () {
      // Segment covers 15 days at 1_000_000; open covers next 15 days at same balance.
      final start = DateTime.now().subtract(const Duration(days: 30));
      final midpoint = DateTime.now().subtract(const Duration(days: 15));

      final segment = InterestPeriodSegment(
        from: DateTime(start.year, start.month, start.day),
        to: DateTime(midpoint.year, midpoint.month, midpoint.day),
        balance: 1000000.0,
        apyRate: 0.0925,
      );

      final withSegments =
          InvestmentCalculator.savingsAccruedInterestWithSegments(
        segments: [segment],
        currentBalance: 1000000.0,
        currentApyRate: 0.0925,
        lastInterestDate: start,
      );
      final legacy = InvestmentCalculator.savingsAccruedInterest(
          1000000.0, 0.0925, start);

      // Results are close but not identical: compound interest splits across
      // sub-periods rather than compounding the first period's earnings into the
      // second. The difference is ≈13 COP on 1_000_000 over 30 days at 9.25%.
      expect(withSegments, closeTo(legacy, 20.0)); // within 20 COP
    });

    test('deposit mid-period increases total interest vs no-deposit scenario', () {
      // Account starts at 1_000_000, then receives 500_000 deposit after 15 days.
      final start = DateTime.now().subtract(const Duration(days: 30));
      final depositDay = DateTime.now().subtract(const Duration(days: 15));

      final segment = InterestPeriodSegment(
        from: DateTime(start.year, start.month, start.day),
        to: DateTime(depositDay.year, depositDay.month, depositDay.day),
        balance: 1000000.0,
        apyRate: 0.0925,
      );

      // After deposit: balance = 1_500_000
      final withDeposit =
          InvestmentCalculator.savingsAccruedInterestWithSegments(
        segments: [segment],
        currentBalance: 1500000.0,
        currentApyRate: 0.0925,
        lastInterestDate: start,
      );
      final withoutDeposit =
          InvestmentCalculator.savingsAccruedInterestWithSegments(
        segments: const [],
        currentBalance: 1000000.0,
        currentApyRate: 0.0925,
        lastInterestDate: start,
      );

      expect(withDeposit, greaterThan(withoutDeposit));
    });

    test('rate change mid-period: each segment uses its own rate', () {
      // 15 days at 9.25%, then 15 days at 7.00% (rate cut).
      final start = DateTime.now().subtract(const Duration(days: 30));
      final rateChangeDay = DateTime.now().subtract(const Duration(days: 15));

      final segment = InterestPeriodSegment(
        from: DateTime(start.year, start.month, start.day),
        to: DateTime(
            rateChangeDay.year, rateChangeDay.month, rateChangeDay.day),
        balance: 1000000.0,
        apyRate: 0.0925,
      );

      final splitResult =
          InvestmentCalculator.savingsAccruedInterestWithSegments(
        segments: [segment],
        currentBalance: 1000000.0,
        currentApyRate: 0.0700,
        lastInterestDate: start,
      );

      // Full 30 days at old rate would be higher (rate was cut).
      final allAtOldRate = InvestmentCalculator.savingsAccruedInterest(
          1000000.0, 0.0925, start);
      // Full 30 days at new rate would be lower.
      final allAtNewRate = InvestmentCalculator.savingsAccruedInterest(
          1000000.0, 0.0700, start);

      expect(splitResult, lessThan(allAtOldRate));
      expect(splitResult, greaterThan(allAtNewRate));
    });

    test('withdrawal mid-period reduces total interest vs no-withdrawal', () {
      final start = DateTime.now().subtract(const Duration(days: 30));
      final withdrawalDay = DateTime.now().subtract(const Duration(days: 15));

      final segment = InterestPeriodSegment(
        from: DateTime(start.year, start.month, start.day),
        to: DateTime(
            withdrawalDay.year, withdrawalDay.month, withdrawalDay.day),
        balance: 1000000.0,
        apyRate: 0.0925,
      );

      // After withdrawal: balance = 500_000
      final withWithdrawal =
          InvestmentCalculator.savingsAccruedInterestWithSegments(
        segments: [segment],
        currentBalance: 500000.0,
        currentApyRate: 0.0925,
        lastInterestDate: start,
      );
      final noChange =
          InvestmentCalculator.savingsAccruedInterestWithSegments(
        segments: const [],
        currentBalance: 1000000.0,
        currentApyRate: 0.0925,
        lastInterestDate: start,
      );

      expect(withWithdrawal, lessThan(noChange));
    });

    test('zero-duration segment is ignored', () {
      final start = DateTime.now().subtract(const Duration(days: 10));
      final sameDay = DateTime(start.year, start.month, start.day);

      final zeroDurationSegment = InterestPeriodSegment(
        from: sameDay,
        to: sameDay, // same day → 0 days
        balance: 1000000.0,
        apyRate: 0.0925,
      );

      final result =
          InvestmentCalculator.savingsAccruedInterestWithSegments(
        segments: [zeroDurationSegment],
        currentBalance: 1000000.0,
        currentApyRate: 0.0925,
        lastInterestDate: start,
      );
      final noSegments =
          InvestmentCalculator.savingsAccruedInterestWithSegments(
        segments: const [],
        currentBalance: 1000000.0,
        currentApyRate: 0.0925,
        lastInterestDate: start,
      );

      expect(result, closeTo(noSegments, 0.001));
    });

    test('multiple segments sum correctly', () {
      final d0 = DateTime.now().subtract(const Duration(days: 40));
      final d1 = DateTime.now().subtract(const Duration(days: 25));
      final d2 = DateTime.now().subtract(const Duration(days: 10));

      final seg1 = InterestPeriodSegment(
        from: DateTime(d0.year, d0.month, d0.day),
        to: DateTime(d1.year, d1.month, d1.day),
        balance: 1000000.0,
        apyRate: 0.0925,
      );
      final seg2 = InterestPeriodSegment(
        from: DateTime(d1.year, d1.month, d1.day),
        to: DateTime(d2.year, d2.month, d2.day),
        balance: 1500000.0, // deposit at d1
        apyRate: 0.0925,
      );

      final result =
          InvestmentCalculator.savingsAccruedInterestWithSegments(
        segments: [seg1, seg2],
        currentBalance: 1500000.0,
        currentApyRate: 0.0925,
        lastInterestDate: d0,
      );

      expect(result, greaterThan(0));
      // Manually verify: result > interest on 1_000_000 for 40 days
      final baseLine = InvestmentCalculator.savingsAccruedInterest(
          1000000.0, 0.0925, d0);
      expect(result, greaterThan(baseLine));
    });
  });

  // ── newAvgCost ───────────────────────────────────────────────────────────────

  group('InvestmentCalculator.newAvgCost', () {
    test('basic weighted average', () {
      // 10 BTC @ 100 + 5 BTC @ 130 → (1000 + 650) / 15 = 110
      final avg = InvestmentCalculator.newAvgCost(
        currentQty: 10.0,
        currentAvgCost: 100.0,
        buyQty: 5.0,
        buyPrice: 130.0,
      );
      expect(avg, closeTo(110.0, 0.001));
    });

    test('buying at same price preserves avg cost', () {
      final avg = InvestmentCalculator.newAvgCost(
        currentQty: 10.0,
        currentAvgCost: 100.0,
        buyQty: 5.0,
        buyPrice: 100.0,
      );
      expect(avg, closeTo(100.0, 0.001));
    });

    test('first purchase (currentQty = 0) sets avg cost to buy price', () {
      final avg = InvestmentCalculator.newAvgCost(
        currentQty: 0.0,
        currentAvgCost: 0.0,
        buyQty: 3.0,
        buyPrice: 250.0,
      );
      expect(avg, closeTo(250.0, 0.001));
    });

    test('returns 0 when totalQty is 0', () {
      final avg = InvestmentCalculator.newAvgCost(
        currentQty: 0.0,
        currentAvgCost: 0.0,
        buyQty: 0.0,
        buyPrice: 100.0,
      );
      expect(avg, 0.0);
    });
  });

  // ── computeTotalValue ────────────────────────────────────────────────────────

  group('InvestmentCalculator.computeTotalValue', () {
    test('cash-only COP account with no holdings', () {
      final account = _account(balance: 500000.0);
      final result = InvestmentCalculator.computeTotalValue(account, []);
      expect(result.cash, closeTo(500000.0, 0.01));
      expect(result.marketValue, closeTo(0.0, 0.01));
      expect(result.total, closeTo(500000.0, 0.01));
      expect(result.totalCop, closeTo(500000.0, 0.01));
      expect(result.isApprox, isFalse);
    });

    test('COP account with COP holdings', () {
      final account = _account(
        balance: 100000.0,
        investmentDetails: InvestmentDetails(
          id: 'd1',
          accountId: 'a1',
          investmentType: InvestmentType.crypto,
          baseCurrency: 'COP',
        ),
      );
      final h = _holding(quantity: 2.0, currentPrice: 200000.0, currency: 'COP');
      final result = InvestmentCalculator.computeTotalValue(account, [h]);
      expect(result.cash, closeTo(100000.0, 0.01));
      expect(result.marketValue, closeTo(400000.0, 0.01));
      expect(result.total, closeTo(500000.0, 0.01));
      expect(result.isApprox, isFalse);
    });

    test('USD account with USD holdings and fx rate', () {
      final account = _account(
        balanceUsd: 1000.0,
        investmentDetails: InvestmentDetails(
          id: 'd1',
          accountId: 'a1',
          investmentType: InvestmentType.stockEtf,
          baseCurrency: 'USD',
        ),
      );
      final h = _holding(quantity: 2.0, currentPrice: 450.0, currency: 'USD');
      final fx = _fxRate(4200.0);
      final result =
          InvestmentCalculator.computeTotalValue(account, [h], fxRate: fx);
      // cash = 1000 USD, marketValue = 900 USD, total = 1900 USD
      expect(result.total, closeTo(1900.0, 0.01));
      // totalCop = 1900 × 4200 = 7.980.000
      expect(result.totalCop, closeTo(7980000.0, 1.0));
      expect(result.isApprox, isTrue);
    });

    test('USD account without fx rate: totalCop equals total, isApprox false', () {
      final account = _account(
        balanceUsd: 500.0,
        investmentDetails: InvestmentDetails(
          id: 'd1',
          accountId: 'a1',
          investmentType: InvestmentType.stockEtf,
          baseCurrency: 'USD',
        ),
      );
      final result = InvestmentCalculator.computeTotalValue(account, []);
      expect(result.totalCop, closeTo(500.0, 0.01));
      expect(result.isApprox, isFalse);
    });
  });
}
