// Uber and Didi authorise the fare at pickup and settle afterwards, so the
// alert that arrives is a hold, not the charge. These are the merchant keys
// as they actually reach this app.

import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/core/parsing/preauth_merchants.dart';
import 'package:budgett_frontend/core/parsing/text_normalizer.dart';

void main() {
  group('chargesInAdvance', () {
    test('catches Uber however the acquirer decorates it', () {
      for (final raw in [
        'UBER BV USD-USD COLO', // the real one, from this user's statement
        'UBER *TRIP',
        'UBER RIDES BOGOTA',
      ]) {
        expect(chargesInAdvance(normalizeMerchant(raw)), isTrue, reason: raw);
      }
    });

    test('catches the other ride-hailing apps', () {
      expect(chargesInAdvance(normalizeMerchant('DIDI MOBILITY')), isTrue);
      expect(chargesInAdvance(normalizeMerchant('CABIFY COLOMBIA')), isTrue);
      expect(chargesInAdvance(normalizeMerchant('INDRIVER')), isTrue);
    });

    test('catches fuel and lodging, which block an estimate', () {
      expect(chargesInAdvance(normalizeMerchant('TERPEL ENVIGADO')), isTrue);
      expect(chargesInAdvance(normalizeMerchant('HOTEL DANN CARLTON')), isTrue);
      expect(chargesInAdvance(normalizeMerchant('AIRBNB * HMQ123')), isTrue);
    });

    test('leaves ordinary merchants alone', () {
      for (final raw in [
        'D1 SABANETA',
        'EXITO SUPER CL 80',
        'SMART FIT 20 DE JULI',
        'RAPPI',
        'NOVAVENTA MEDELLIN C',
      ]) {
        expect(chargesInAdvance(normalizeMerchant(raw)), isFalse, reason: raw);
      }
    });

    test('a message with no merchant follows the ordinary default', () {
      expect(chargesInAdvance(null), isFalse);
      expect(chargesInAdvance(''), isFalse);
    });

    test('the explanation is shown only where it applies', () {
      expect(preauthReason(normalizeMerchant('UBER *TRIP')), isNotNull);
      expect(preauthReason(normalizeMerchant('D1 SABANETA')), isNull);
    });
  });
}
