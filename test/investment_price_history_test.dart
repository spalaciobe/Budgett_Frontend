import 'package:flutter_test/flutter_test.dart';
import 'package:budgett_frontend/data/models/investment_price_history_model.dart';
import 'package:budgett_frontend/data/models/investment_purchase_event_model.dart';

void main() {
  group('InvestmentPriceHistory', () {
    test('parses numeric fields and computes position value', () {
      final row = InvestmentPriceHistory.fromJson({
        'id': 'ph1',
        'user_id': 'u1',
        'account_id': 'a1',
        'holding_id': 'h1',
        'symbol': 'BTC',
        'asset_class': 'crypto',
        'currency': 'COP',
        'price': 280000000,
        'quantity_snapshot': 0.0025,
        'source': 'coingecko',
        'market_date': '2026-05-27',
        'fetched_at': '2026-05-27T23:00:00Z',
      });

      expect(row.symbol, 'BTC');
      expect(row.marketDate, DateTime(2026, 5, 27));
      expect(row.positionValue, closeTo(700000, 0.001));
    });

    test('defaults nullable numeric values to zero', () {
      final row = InvestmentPriceHistory.fromJson({
        'id': 'ph1',
        'user_id': 'u1',
        'account_id': 'a1',
        'holding_id': 'h1',
        'symbol': 'ICOLCAP',
        'asset_class': 'etf',
        'currency': null,
        'price': null,
        'quantity_snapshot': null,
        'source': null,
        'market_date': '2026-05-27',
        'fetched_at': '2026-05-27T23:00:00Z',
      });

      expect(row.currency, 'COP');
      expect(row.price, 0);
      expect(row.quantitySnapshot, 0);
      expect(row.source, 'manual');
    });
  });

  group('InvestmentPurchaseEvent', () {
    test('parses buy transaction date and quantity', () {
      final event = InvestmentPurchaseEvent.fromTransactionJson({
        'holding_id': 'h1',
        'date': '2026-05-20',
        'amount': 120000,
        'holding_qty_delta': 0.004,
      });

      expect(event.holdingId, 'h1');
      expect(event.date, DateTime(2026, 5, 20));
      expect(event.quantity, 0.004);
      expect(event.amount, 120000);
      expect(event.source, 'transaction');
    });

    test('created_at fallback marks legacy holdings', () {
      final event = InvestmentPurchaseEvent.fromHoldingCreatedAt(
        holdingId: 'h2',
        createdAt: DateTime(2026, 4, 14),
        quantity: 7,
        amount: 1014860,
      );

      expect(event.source, 'created_at');
      expect(event.date, DateTime(2026, 4, 14));
      expect(event.quantity, 7);
    });
  });
}
