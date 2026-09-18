import 'package:flutter_test/flutter_test.dart';

import 'package:budgett_frontend/data/models/merchant_alias_model.dart';

const _novaventa = MerchantAlias(
  id: 'alias-1',
  pattern: 'novaventa medellin c',
  displayName: 'Novaventa',
  categoryId: 'cat-food',
);

const _rappi = MerchantAlias(
  id: 'alias-2',
  matchType: 'contains',
  pattern: 'rappi',
  displayName: 'Rappi',
  categoryId: 'cat-food',
);

const _aliases = [_novaventa, _rappi];

void main() {
  group('the rule behind a recorded movement', () {
    test('is the one the capture was stamped with', () {
      final found = MerchantAlias.resolveForMovement(
        _aliases,
        aliasId: 'alias-2',
        merchantKey: 'novaventa medellin c',
      );
      expect(found, same(_rappi));
    });

    test("falls back to the bank's text when nothing was stamped", () {
      // What a merchant taught from the review inbox looks like: the rule was
      // written, the link back to it never was.
      final found = MerchantAlias.resolveForMovement(
        _aliases,
        merchantKey: 'novaventa medellin c',
      );
      expect(found, same(_novaventa));
    });

    test('survives the movement being renamed', () {
      // The bug this guards: looking the rule up by the *edited* name found
      // nothing, so saving wrote a second rule keyed on "Mercado" — a string
      // no bank ever sends, matching nothing, while the real rule kept the
      // old category.
      final found = MerchantAlias.resolveForMovement(
        _aliases,
        aliasId: 'alias-1',
        merchantKey: 'novaventa medellin c',
        recordedName: 'Novaventa',
      );
      expect(found, same(_novaventa));
    });

    test('uses the recorded name for a movement typed by hand', () {
      final found = MerchantAlias.resolveForMovement(
        _aliases,
        recordedName: 'Novaventa',
      );
      expect(found, same(_novaventa));
    });

    test('is nothing when the merchant has never been taught', () {
      expect(
        MerchantAlias.resolveForMovement(
          _aliases,
          merchantKey: 'panaderia la esquina',
          recordedName: 'Panaderia La Esquina',
        ),
        isNull,
      );
    });

    test('is nothing when there is nothing to go on', () {
      expect(
        MerchantAlias.resolveForMovement(_aliases, recordedName: '  '),
        isNull,
      );
    });
  });
}
