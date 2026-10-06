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

  group('transfers and QR — where the counterparty IS the merchant', () {
    // Verbatim Bancolombia messages. Most of this user's spending is Bre-B
    // keys, account transfers and QR, none of which name a shop. The
    // destination (a key, an account number, or the person) has to become the
    // merchant, otherwise there is nothing stable to attach an alias to and
    // every transfer stays unclassifiable forever.

    test('QR payment to a Bre-B key', () {
      final result = _parse(
        'Bancolombia: SEBASTIAN PALACIO BETANCUR pagaste \$10,000.00 por '
        'codigo QR desde tu cuenta *1951 a la llave 0039635842 el 20/09/2026 '
        'a las 15:27. Con codigo QR es facil y de una. Dudas al 018000912345.',
        receivedAt: DateTime(2026, 9, 20, 15, 28),
      );

      expect(result.status, ParseStatus.parsed);
      expect(result.amount, 10000.0);
      // The article and the noun are stripped; the key itself is the identity.
      expect(result.merchantKey, 'LLAVE 0039635842');
      // The source account, never the destination, is the card.
      expect(result.cardLast4, '1951');
      expect(result.occurredAt, DateTime(2026, 9, 20, 15, 27));
    });

    test('transfer to an account number', () {
      final result = _parse(
        'Bancolombia: Transferiste \$20,000 desde tu cuenta *1951 a la cuenta '
        '*01768288204 el 20/09/2026 a las 09:16. ¿Dudas? Llamanos al '
        '018000931987. Estamos cerca.',
        receivedAt: DateTime(2026, 9, 20, 9, 17),
      );

      expect(result.kind, MessageKind.transferOut);
      expect(result.amount, 20000.0);
      expect(result.merchantKey, 'CUENTA 01768288204');
      expect(result.cardLast4, '1951');
    });

    test('a named person wins over the key that precedes them', () {
      // "a la llave 98648320 … a EDISON ARANGO CORREA": the name is the
      // useful identity, and it appears AFTER the key, so only scanning the
      // first "a" would miss it.
      final result = _parse(
        'Bancolombia: SEBASTIAN, transferiste \$12,000.00 a la llave 98648320 '
        'desde tu cuenta *1951 a EDISON ARANGO CORREA el 20/09/26 a las 08:41. '
        'Con Bre-b es de una y gratis. Dudas al 018000912345.',
        receivedAt: DateTime(2026, 9, 20, 8, 42),
      );

      expect(result.kind, MessageKind.transferOut);
      expect(result.amount, 12000.0);
      expect(result.merchantKey, 'EDISON ARANGO CORREA');
      expect(result.cardLast4, '1951');
      expect(result.occurredAt, DateTime(2026, 9, 20, 8, 41));
    });

    test('an identifier keeps its digits — they are its identity', () {
      // The store-code stripper would otherwise collapse every key to
      // "LLAVE", making all transfers share a single useless alias.
      expect(normalizeMerchant('llave 0039635842'), 'LLAVE 0039635842');
      expect(normalizeMerchant('cuenta *01768288204'), 'CUENTA 01768288204');
      // A real store code after a plain name is still noise.
      expect(normalizeMerchant('EXITO 1234'), 'EXITO');
    });

    test('transfers out can post unattended once taught', () {
      // They become type=expense and need no destination account, so the
      // blanket exclusion only meant this user's most common payment could
      // never be automated.
      expect(MessageKind.transferOut.transactionType, 'expense');
      expect(MessageKind.transferOut.isAutoPostable, isTrue);
      // A card payment is a real transfer between two accounts — still manual.
      expect(MessageKind.payment.isAutoPostable, isFalse);
    });
  });

  group('incoming transfers name the sender, not the sales pitch', () {
    test('the trailing pitch is not a counterparty', () {
      // Six real transfers were recorded as "Una Y Gratis": the sender's name
      // sits BEFORE the amount here, so the search of the text after it found
      // "Con llaves es de una y gratis" and took that.
      final result = _parse(
        'Alertas y Notificaciones Bancolombia: SEBASTIAN, recibiste una '
        'transferencia de LAURA MARIA MORALES MONSALVE por \$60,000.00 en tu '
        'cuenta *1951 conectada a la llave 1001687721 el 04/10/26 a las 19:10. '
        'Con llaves es de una y gratis. Dudas al 018000912345.',
        receivedAt: DateTime(2026, 10, 4, 19, 11),
      );

      expect(result.kind, MessageKind.transferIn);
      expect(result.amount, 60000.0);
      expect(result.merchantKey, 'LAURA MARIA MORALES MONSALVE');
    });

    test('the account the money landed in is not part of the name', () {
      final result = _parse(
        'Bancolombia: Recibiste una transferencia por \$38,000 de FERNANDO '
        'PALACIO en tu cuenta **1951, el 27/09/2026 a las 17:50.',
        receivedAt: DateTime(2026, 9, 27, 17, 51),
      );

      expect(result.amount, 38000.0);
      expect(result.merchantKey, 'FERNANDO PALACIO');
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
      // A transfer out becomes a plain expense, so once an alias supplies the
      // account and category there is nothing left to ask about.
      expect(result.kind!.transactionType, 'expense');
      expect(result.kind!.isAutoPostable, isTrue);
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

  group('currency comes from the marker, not the prose', () {
    // Verbatim. The merchant's NAME contains "USD", and inferring currency
    // from the whole text read a ~24,000 peso ride as 23,916 dollars — a
    // 4,000x overstatement that also hid it from every budget aggregation,
    // since those all filter on currency='COP'.
    const uber =
        'Bancolombia: Compraste COP23.916,36 en UBER BV USD-USD COLO, el '
        '29/09/2026 a las 09:49. Esta compra esta asociada a T.Cred *8225.';

    test('an explicit COP marker beats a stray USD in the merchant name', () {
      final result = _parse(uber, receivedAt: DateTime(2026, 9, 29, 9, 50));
      expect(result.amount, 23916.36);
      expect(result.currency, 'COP');
    });

    test('wording still decides when the number carries no marker', () {
      // 120, not 25: a bare number under 100 is rejected as implausible for
      // money, so a smaller figure would test the plausibility rule instead.
      final result = _parse('Compra por 120 dolares en SPOTIFY');
      expect(result.amount, 120);
      expect(result.currency, 'USD');
    });

    test('an explicit US\$ marker is honoured', () {
      final result = _parse('Compra por US\$12.50 en SPOTIFY');
      expect(result.currency, 'USD');
      expect(result.amount, 12.5);
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

  group('tap-to-pay wallets', () {
    // Verbatim from this user's inbox. It had sat unparsed because the body
    // carries no action verb and no "en <merchant>" — the merchant is the
    // notification title.
    const walletPackage = 'com.google.android.apps.walletnfcrel';

    test('reads a Google Wallet payment', () {
      final result = _parse(
        'COP27,500.00 with Tarjeta Visa •1673',
        sourceKey: walletPackage,
        title: 'REST Y CAFET EL PIEL R',
      );

      expect(result.status, ParseStatus.parsed);
      expect(result.kind, MessageKind.purchase);
      expect(result.amount, 27500);
      expect(result.currency, 'COP');
      expect(result.merchantRaw, 'REST Y CAFET EL PIEL R');
      expect(result.cardLast4, '1673');
    });

    test('scores high enough to teach itself a rule', () {
      // The structure is unambiguous even though the package is not a bank,
      // so it must not be condemned to a review every time.
      final result = _parse(
        'COP27,500.00 with Tarjeta Visa •1673',
        sourceKey: walletPackage,
        title: 'REST Y CAFET EL PIEL R',
      );
      expect(result.confidence, greaterThanOrEqualTo(0.8));
    });

    test('a wallet message that is not a payment stays unparsed', () {
      final result = _parse(
        'Agregaste una tarjeta nueva a tu wallet',
        sourceKey: walletPackage,
        title: 'Google Wallet',
      );
      expect(result.status, isNot(ParseStatus.parsed));
    });

    test('the shape alone does not fire outside a wallet package', () {
      // Same body from Gmail is a receipt, and the title is the sender.
      final result = _parse(
        'COP27,500.00 with Tarjeta Visa •1673',
        sourceKey: 'com.google.android.gm',
        title: 'Recibos',
      );
      expect(result.merchantRaw, isNot('Recibos'));
    });
  });

  group('card digits', () {
    test('reads a bullet mask with the brand in between', () {
      expect(findCardLast4('with Tarjeta Visa •1673'), '1673');
      expect(findCardLast4('Mastercard ••8844'), '8844');
    });

    test('still reads the asterisk masks the banks use', () {
      expect(findCardLast4('con tu T.Cred *8225'), '8225');
      expect(findCardLast4('Tarjeta terminada en 4821'), '4821');
    });

    test('a full account number is not a card mask', () {
      // "transferiste a la cuenta *01768288204" is a destination, not four
      // digits to map an account to — reading it as one would link the wrong
      // account to every transfer.
      expect(findCardLast4('cuenta *01768288204'), isNull);
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
