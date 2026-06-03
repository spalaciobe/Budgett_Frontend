import 'package:budgett_frontend/data/models/investment_price_history_model.dart';
import 'package:budgett_frontend/presentation/providers/portfolio_provider.dart';
import 'package:flutter_test/flutter_test.dart';

InvestmentPriceHistory _row({
  required String holdingId,
  required String date,
  required double price,
  required double qty,
  String currency = 'COP',
}) {
  return InvestmentPriceHistory(
    id: '$holdingId-$date',
    userId: 'u1',
    accountId: 'a1',
    holdingId: holdingId,
    symbol: holdingId,
    assetClass: 'crypto',
    currency: currency,
    price: price,
    quantitySnapshot: qty,
    source: 'coingecko',
    marketDate: DateTime.parse(date),
    fetchedAt: DateTime.parse(date),
  );
}

void main() {
  group('buildTotalValueSeries', () {
    test('forward-fills each holding across the union of dates', () {
      final rows = [
        _row(holdingId: 'A', date: '2026-01-01', price: 100, qty: 2), // 200
        _row(holdingId: 'A', date: '2026-01-03', price: 110, qty: 2), // 220
        _row(holdingId: 'B', date: '2026-01-02', price: 50, qty: 4), // 200
      ];

      final series = buildTotalValueSeries(rows, (v, _) => v);

      expect(series.map((p) => p.date), [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 3),
      ]);
      // Jan 1: only A. Jan 2: A held flat at 200 + B 200. Jan 3: A 220 + B flat 200.
      expect(series.map((p) => p.value), [200, 400, 420]);
    });

    test('applies the currency conversion callback', () {
      final rows = [
        _row(
            holdingId: 'U',
            date: '2026-01-01',
            price: 10,
            qty: 1,
            currency: 'USD'),
      ];

      final series = buildTotalValueSeries(
        rows,
        (v, c) => c == 'USD' ? v * 4000 : v,
      );

      expect(series.single.value, 40000);
    });

    test('returns empty for no rows', () {
      expect(buildTotalValueSeries(const [], (v, _) => v), isEmpty);
    });
  });
}
