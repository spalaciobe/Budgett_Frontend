// Parser tests driven by the shapes Colombian issuers actually send.
//
// These are the regression net for the feature: every time a bank rewords an
// alert and an expense goes missing, the fix belongs here first as a failing
// case, then in `_kindRules` / the extractors.

import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/core/parsing/amount_parser.dart';
import 'package:budgett_frontend/core/parsing/expense_message_parser.dart';
import 'package:budgett_frontend/core/parsing/issuer_registry.dart';
import 'package:budgett_frontend/core/parsing/message_kind.dart';
import 'package:budgett_frontend/core/parsing/text_normalizer.dart';

const _parser = ExpenseMessageParser();

/// 2026-09-17 15:44 local — the reference "now" for every case.
final _now = DateTime(2026, 9, 17, 15, 44);

ParsedMessage _parse(
  String body, {
  String sourceKey = '890255',
  String title = '',
  DateTime? receivedAt,
  String? pinnedIssuer,
}) =>
    _parser.parse(
      sourceKey: sourceKey,
      title: title,
      body: body,
      receivedAt: receivedAt ?? _now,
      pinnedIssuer: pinnedIssuer,
    );

void main() {
  group('amount parsing', () {
    test('resolves separators from the shape of the token', () {
      // es_CO: dot groups, comma decimals.
      expect(parseAmountToken('45.900,00'), 45900.0);
      expect(parseAmountToken('1.234.567'), 1234567.0);
      // A three-digit tail after a single dot is a thousands group in Colombia.
      expect(parseAmountToken('1.500'), 1500.0);
      // A two-digit tail is a decimal.
      expect(parseAmountToken('10.50'), 10.5);
      expect(parseAmountToken('12,50'), 12.5);
      // en_US shape, which some issuers still send.
      expect(parseAmountToken('45,900.00'), 45900.0);
      expect(parseAmountToken('900'), 900.0);
    });

    test('prefers the value carrying a currency marker', () {
      // The balance that trails the alert must not win over the amount.
      final match = findAmount('Pagaste \$18.900 en Rappi. Saldo \$1.250.000');
      expect(match, isNotNull);
      expect(match!.value, 18900.0);
      expect(match.currency, 'COP');
    });

    test('recognises USD markers', () {
      final match = findAmount('Compra por US\$12.50 en SPOTIFY');
      expect(match!.currency, 'USD');
      expect(match.value, 12.5);
    });

    test('ignores long digit runs with no marker', () {
      // The 018000 support line is not an amount.
      expect(findAmount('Inquietudes al 018000931987'), isNull);
    });
  });

  group('merchant normalisation', () {
    test('strips accents, aggregator glue and trailing noise', () {
      expect(normalizeMerchant('Éxito Super  Cl 80 BOG'), 'EXITO SUPER CL 80');
      expect(normalizeMerchant('MERCADOPAGO*SPOTIFY'), 'MERCADOPAGO SPOTIFY');
      expect(normalizeMerchant('RAPPI 1234 BOGOTA'), 'RAPPI');
      expect(normalizeMerchant('D1 #0012'), 'D1');
    });

    test('keeps a city word that is part of the name', () {
      // Only a trailing city token is noise.
      expect(normalizeMerchant('BOGOTA BEER COMPANY'), 'BOGOTA BEER COMPANY');
    });

    test('is stable — alias keys depend on it', () {
      const raw = 'Exito  super cl 80';
      expect(normalizeMerchant(raw), normalizeMerchant(normalizeMerchant(raw)));
    });
  });

  group('Bancolombia', () {
    test('purchase SMS yields every field', () {
      final result = _parse(
        'Bancolombia le informa Compra por \$45.900,00 en EXITO SUPER CL 80 '
        '04/09/2026 14:32. Tarjeta *1234. Inquietudes al 018000931987',
        receivedAt: DateTime(2026, 9, 4, 14, 33),
      );

      expect(result.status, ParseStatus.parsed);
      expect(result.kind, MessageKind.purchase);
      expect(result.issuerKey, 'bancolombia');
      expect(result.amount, 45900.0);
      expect(result.currency, 'COP');
      expect(result.merchantKey, 'EXITO SUPER CL 80');
      expect(result.cardLast4, '1234');
      expect(result.occurredAt, DateTime(2026, 9, 4, 14, 32));
      // Bank + merchant + card + timestamp: confident enough to post alone.
      expect(result.confidence, greaterThanOrEqualTo(0.9));
    });

    test('"pagaste … con tu producto" stops the merchant at "con"', () {
      final result = _parse(
          'Bancolombia: Pagaste \$34.500 en RAPPI con tu producto *0123');

      expect(result.kind, MessageKind.purchase);
      expect(result.merchantKey, 'RAPPI');
      expect(result.cardLast4, '0123');
    });

    test('ATM withdrawal', () {
      final result = _parse(
          'Bancolombia le informa retiro por \$200.000 en CAJERO CC ANDINO '
          'BOGOTA 17/09/2026 10:05',
          receivedAt: DateTime(2026, 9, 17, 10, 6));

      expect(result.kind, MessageKind.withdrawal);
      expect(result.amount, 200000.0);
      expect(result.merchantKey, 'CAJERO CC ANDINO');
    });

    test('incoming transfer names the sender, not a merchant', () {
      final result = _parse(
          'Bancolombia: Recibiste una transferencia por \$500.000 de JUAN PEREZ');

      expect(result.kind, MessageKind.transferIn);
      expect(result.kind!.transactionType, 'income');
      expect(result.amount, 500000.0);
      expect(result.merchantKey, 'JUAN PEREZ');
    });
  });

  group('real messages from the field', () {
    // Verbatim Bancolombia SMS. Every wart here was found by running this
    // exact text, not by imagining a format: "COP" glued to the number, the
    // "T.Cred" abbreviation, a truncated city tail, and two support phone
    // numbers that must not be read as amounts.
    const novaventa =
        'Bancolombia: Compraste COP2.200,00 en NOVAVENTA MEDELLIN C con tu '
        'T.Cred *8225, el 17/09/2026 a las 14:56. Si tienes dudas, '
        'encuentranos aqui: 6045109095 o 018000931987. Estamos cerca.';

    test('parses every field', () {
      final result = _parse(novaventa,
          sourceKey: '87400', receivedAt: DateTime(2026, 9, 17, 14, 57));

      expect(result.status, ParseStatus.parsed);
      expect(result.kind, MessageKind.purchase);
      expect(result.issuerKey, 'bancolombia');
      // "COP2.200,00" with no space after the marker.
      expect(result.amount, 2200.0);
      expect(result.currency, 'COP');
      expect(result.cardLast4, '8225');
      expect(result.occurredAt, DateTime(2026, 9, 17, 14, 56));
      expect(result.confidence, greaterThanOrEqualTo(0.9));
    });

    test('the support phone numbers are not read as the amount', () {
      final result = _parse(novaventa,
          sourceKey: '87400', receivedAt: DateTime(2026, 9, 17, 14, 57));
      expect(result.amount, 2200.0);
      expect(result.amount, isNot(6045109095));
      expect(result.amount, isNot(18000931987));
    });

    test('the same shop in another city gives the same alias key', () {
      // The key IS the alias key. If the truncated city tail survived, the
      // user would have to teach the same shop once per city.
      final medellin = _parse(novaventa,
          sourceKey: '87400', receivedAt: DateTime(2026, 9, 17, 14, 57));
      final bogota = _parse(
          'Bancolombia: Compraste COP15.000,00 en NOVAVENTA BOGOTA D con tu '
          'T.Cred 8225, el 17/09/2026 a las 15:10.',
          sourceKey: '87400',
          receivedAt: DateTime(2026, 9, 17, 15, 11));

      expect(medellin.merchantKey, 'NOVAVENTA');
      expect(bogota.merchantKey, 'NOVAVENTA');
      // Also proves the abbreviation is read without an asterisk.
      expect(bogota.cardLast4, '8225');
    });

    test('a truncated city tail is only stripped after a real city', () {
      expect(normalizeMerchant('NOVAVENTA MEDELLIN C'), 'NOVAVENTA');
      // A name that genuinely ends in a letter must survive.
      expect(normalizeMerchant('PLAN B'), 'PLAN B');
      expect(normalizeMerchant('VITAMINA C'), 'VITAMINA C');
    });
  });

  group('other issuers', () {
    test('Nequi outgoing transfer', () {
      final result = _parse(
        'Enviaste \$20.000 a Sebastian P. Saldo disponible \$130.000',
        sourceKey: 'com.nequi.MobileApp',
        title: 'Nequi',
      );

      expect(result.issuerKey, 'nequi');
      expect(result.kind, MessageKind.transferOut);
      expect(result.amount, 20000.0);
      expect(result.merchantKey, 'SEBASTIAN P');
      // Transfers need a destination account, so they never post unattended.
      expect(result.kind!.isAutoPostable, isFalse);
    });

    test('Nu purchase, issuer resolved from the package name', () {
      final result = _parse(
        'Compra aprobada de \$32.500 en MERCADOPAGO*SPOTIFY',
        sourceKey: 'com.nu.production',
      );

      expect(result.issuerKey, 'nu');
      expect(result.kind, MessageKind.purchase);
      expect(result.amount, 32500.0);
      expect(result.merchantKey, 'MERCADOPAGO SPOTIFY');
    });

    test('Davivienda trims the city and reads T.Credito', () {
      final result = _parse(
        'Davivienda: Compra aprobada por \$89.000 en FALABELLA BOG, '
        'T.Credito *4321, 17/09/26 15:44',
      );

      expect(result.issuerKey, 'davivienda');
      expect(result.merchantKey, 'FALABELLA');
      expect(result.cardLast4, '4321');
      expect(result.occurredAt, DateTime(2026, 9, 17, 15, 44));
    });

    test('BBVA "terminada en" card format', () {
      final result = _parse(
        'BBVA: Compra por \$75.000 en ARA CL 100 con tarjeta terminada en 1234',
      );

      expect(result.issuerKey, 'bbva');
      expect(result.cardLast4, '1234');
      expect(result.merchantKey, 'ARA CL 100');
    });

    test('a pinned issuer overrides detection', () {
      // An opaque short code the user mapped to their bank by hand.
      final result = _parse('Compra por \$10.000 en TIENDA',
          sourceKey: '85432', pinnedIssuer: 'colpatria');
      expect(result.issuerKey, 'colpatria');
      expect(issuerDisplayName(result.issuerKey), 'Scotiabank Colpatria');
    });
  });

  group('messages that are not movements', () {
    test('one-time passwords are ignored, digits and all', () {
      final result = _parse(
          'Bancolombia: Tu clave dinamica es 123456. No la compartas con nadie');

      expect(result.status, ParseStatus.ignored);
      expect(result.ignoredReason, 'One-time password');
      expect(result.amount, isNull);
    });

    test('marketing is ignored', () {
      final result = _parse(
          'Felicitaciones, tienes un cupo preaprobado por \$5.000.000');
      expect(result.status, ParseStatus.ignored);
    });

    test('a rejected purchase is parsed but flagged as declined', () {
      final result = _parse(
          'BBVA: Compra por \$150.000 en HOMECENTER rechazada por fondos '
          'insuficientes');

      expect(result.kind, MessageKind.declined);
      expect(result.kind!.isAutoPostable, isFalse);
    });

    test('a message with no amount is unparsed, not ignored', () {
      final result = _parse('Bancolombia: tu compra fue registrada');
      expect(result.status, ParseStatus.unparsed);
      expect(result.isUsable, isFalse);
    });
  });

  group('timestamps', () {
    test('falls back to the arrival time when none is given', () {
      final result = _parse('Compra por \$10.000 en TIENDA');
      expect(result.occurredAt, _now);
    });

    test('reads a bare time against the arrival day', () {
      final occurred = findOccurredAt('Compra a las 09:15 en TIENDA', _now);
      expect(occurred, DateTime(2026, 9, 17, 9, 15));
    });

    test('distrusts a date far from arrival — that is a due date', () {
      expect(findOccurredAt('Paga antes del 30/10/2026', _now), isNull);
    });

    test('rejects an impossible date instead of rolling it over', () {
      expect(findOccurredAt('31/02/2026 10:00', DateTime(2026, 2, 28)), isNull);
    });

    test('reads a textual month', () {
      final occurred =
          findOccurredAt('Compra el 17 sep 2026 14:05', _now);
      expect(occurred, DateTime(2026, 9, 17, 14, 5));
    });
  });

  group('confidence', () {
    test('a bare alert stays below the auto-post threshold', () {
      // No issuer, no card, no timestamp: the pipeline must ask.
      final result = _parse('Compra por \$25.000 en TIENDA', sourceKey: '1111');
      expect(result.issuerKey, isNull);
      expect(result.confidence, lessThan(0.8));
    });

    test('a complete alert clears it', () {
      final result = _parse(
        'Bancolombia le informa Compra por \$25.000 en EXITO 17/09/2026 15:40. '
        'Tarjeta *1234',
      );
      expect(result.confidence, greaterThanOrEqualTo(0.8));
    });
  });
}
