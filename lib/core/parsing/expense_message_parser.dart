/// Turns a raw notification / SMS into a structured movement.
///
/// The parser is deliberately keyword-and-shape driven rather than one big
/// regex per bank: issuers reword their alerts often, and a template that
/// stops matching would silently drop expenses. Instead we look for
///
///   1. a reason to ignore the message entirely (OTP, promo, balance poll),
///   2. an action keyword that tells us WHAT happened,
///   3. an amount with a currency marker,
///   4. a counterparty (merchant or person) around the action keyword,
///   5. optional card last-4 and an explicit timestamp,
///
/// and score the result. A low score is not a failure — it just means the
/// message lands in the inbox instead of posting by itself.
library;

import 'amount_parser.dart';
import 'issuer_registry.dart';
import 'message_kind.dart';
import 'text_normalizer.dart';

enum ParseStatus {
  /// Amount and kind found — usable, subject to [ParsedMessage.confidence].
  parsed,

  /// Looks financial but we could not pull out an amount or an action.
  unparsed,

  /// Positively identified as something that is not a movement.
  ignored;

  String get wireName => name;
}

class ParsedMessage {
  final ParseStatus status;
  final MessageKind? kind;
  final String? issuerKey;
  final double? amount;
  final String? currency;

  /// Merchant/counterparty exactly as the bank wrote it.
  final String? merchantRaw;

  /// [merchantRaw] run through [normalizeMerchant] — the alias lookup key.
  final String? merchantKey;

  final String? cardLast4;

  /// Payment instant. Falls back to the message arrival time.
  final DateTime occurredAt;

  /// 0..1. Drives whether the message can post without review.
  final double confidence;

  /// Why the message was ignored, for the "Ignored" tab in the inbox.
  final String? ignoredReason;

  const ParsedMessage({
    required this.status,
    required this.occurredAt,
    this.kind,
    this.issuerKey,
    this.amount,
    this.currency,
    this.merchantRaw,
    this.merchantKey,
    this.cardLast4,
    this.confidence = 0,
    this.ignoredReason,
  });

  bool get isUsable =>
      status == ParseStatus.parsed && amount != null && kind != null;
}

// ─── ignore rules ────────────────────────────────────────────────────────────

/// Phrases that mean "this is not a movement". Checked before anything else,
/// because an OTP message ("tu clave dinamica es 123456") contains digits that
/// would otherwise be read as an amount.
const _ignoreRules = <(String, String)>[
  ('clave dinamica', 'One-time password'),
  ('clave temporal', 'One-time password'),
  ('codigo de verificacion', 'Verification code'),
  ('codigo de seguridad', 'Verification code'),
  ('token', 'Verification code'),
  ('no compartas', 'Verification code'),
  ('no la compartas', 'Verification code'),
  ('es tu otp', 'Verification code'),
  ('inicio de sesion', 'Security notice'),
  ('cambio de clave', 'Security notice'),
  ('actualizacion de datos', 'Security notice'),
  ('cupo preaprobado', 'Marketing'),
  ('preaprobado', 'Marketing'),
  ('felicitaciones', 'Marketing'),
  ('aprovecha', 'Marketing'),
  ('descuento del', 'Marketing'),
  ('invitamos', 'Marketing'),
  ('conoce nuestro', 'Marketing'),
  ('extracto disponible', 'Statement notice'),
  ('factura disponible', 'Statement notice'),
  ('proximo a vencer', 'Reminder'),
  ('fecha limite de pago', 'Reminder'),
  ('recordatorio de pago', 'Reminder'),
  ('no olvides pagar', 'Reminder'),
];

// ─── action keywords ─────────────────────────────────────────────────────────

/// Keyword → kind, most specific first. The first hit wins, so "pago de tu
/// tarjeta" must be tested before the bare "pago".
const _kindRules = <(String, MessageKind)>[
  // Rejections first: "compra rechazada" must not read as a purchase.
  ('rechazada', MessageKind.declined),
  ('rechazado', MessageKind.declined),
  ('declinada', MessageKind.declined),
  ('no fue aprobada', MessageKind.declined),
  ('no aprobada', MessageKind.declined),
  ('fondos insuficientes', MessageKind.declined),
  ('saldo insuficiente', MessageKind.declined),
  ('intento de compra', MessageKind.declined),

  // Reversals.
  ('reverso', MessageKind.refund),
  ('reversada', MessageKind.refund),
  ('reversado', MessageKind.refund),
  ('anulacion', MessageKind.refund),
  ('anulada', MessageKind.refund),
  ('devolucion', MessageKind.refund),
  ('te devolvimos', MessageKind.refund),

  // Card payments (user paying the card down).
  ('pago de tu tarjeta', MessageKind.payment),
  ('pago a tu tarjeta', MessageKind.payment),
  ('abono a tu tarjeta', MessageKind.payment),
  ('pagaste tu tarjeta', MessageKind.payment),
  ('pago a tarjeta de credito', MessageKind.payment),
  ('abono a su tarjeta', MessageKind.payment),

  // Cash out.
  ('retiro', MessageKind.withdrawal),
  ('retiraste', MessageKind.withdrawal),
  ('avance en efectivo', MessageKind.withdrawal),
  ('avance por', MessageKind.withdrawal),

  // Money in.
  ('recibiste una transferencia', MessageKind.transferIn),
  ('recibio una transferencia', MessageKind.transferIn),
  ('recibiste', MessageKind.transferIn),
  ('te enviaron', MessageKind.transferIn),
  ('te consignaron', MessageKind.transferIn),
  ('te transfirieron', MessageKind.transferIn),
  ('consignacion por', MessageKind.transferIn),
  ('abono por', MessageKind.transferIn),
  ('entro plata', MessageKind.transferIn),
  ('nomina por', MessageKind.transferIn),

  // Money out to a person / another account.
  ('transferiste', MessageKind.transferOut),
  ('enviaste', MessageKind.transferOut),
  ('transferencia por', MessageKind.transferOut),
  ('transferencia de', MessageKind.transferOut),
  ('envio de dinero', MessageKind.transferOut),
  ('pago pse', MessageKind.transferOut),

  // Purchases — broadest, tested last.
  ('compra aprobada', MessageKind.purchase),
  ('compra por', MessageKind.purchase),
  ('compra de', MessageKind.purchase),
  ('compraste', MessageKind.purchase),
  ('tu compra', MessageKind.purchase),
  ('compra', MessageKind.purchase),
  ('pagaste', MessageKind.purchase),
  ('pago exitoso', MessageKind.purchase),
  ('pago aprobado', MessageKind.purchase),
  ('transaccion aprobada', MessageKind.purchase),
  ('cargo por', MessageKind.purchase),
  ('cargo a tu', MessageKind.purchase),
];

// ─── field extractors ────────────────────────────────────────────────────────

/// `*1234`, `terminada en 1234`, `T.Credito *4321`, `xxxx1234`.
final _last4Patterns = <RegExp>[
  RegExp(r'(?:terminad[ao]\s+en|termina\s+en|final(?:izad[ao])?\s+en)\s*[*xX]*(\d{3,4})',
      caseSensitive: false),
  // Issuers abbreviate heavily: "T.Credito", "T.Cred", "T.Deb", "Tarjeta".
  RegExp(r'(?:tarjeta|producto|cuenta|t\.?\s*(?:cred(?:ito)?|deb(?:ito)?)|tc|td)\s*(?:n[o°.]?\s*)?[*xX#]*(\d{3,4})\b',
      caseSensitive: false),
  RegExp(r'[*]{1,4}\s?(\d{3,4})\b'),
  RegExp(r'[xX]{2,4}\s?(\d{3,4})\b'),
];

String? findCardLast4(String text) {
  for (final pattern in _last4Patterns) {
    final match = pattern.firstMatch(text);
    if (match != null) return match.group(1);
  }
  return null;
}

const _monthAbbreviations = {
  'ene': 1, 'feb': 2, 'mar': 3, 'abr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'ago': 8, 'sep': 9, 'set': 9, 'oct': 10, 'nov': 11, 'dic': 12,
};

final _dmyPattern = RegExp(
    r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b(?:\s*(?:a\s+las\s*)?(\d{1,2}):(\d{2})(?::(\d{2}))?)?');
final _ymdPattern = RegExp(
    r'\b(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})\b(?:[\sT]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?');
final _textualDatePattern = RegExp(
    r'\b(\d{1,2})\s*(?:de\s+)?(ene|feb|mar|abr|may|jun|jul|ago|sep|set|oct|nov|dic)[a-z]*\.?\s*(?:de\s+)?(\d{2,4})?(?:\s*(?:a\s+las\s*)?(\d{1,2}):(\d{2}))?',
    caseSensitive: false);
final _timeOnlyPattern =
    RegExp(r'\b(?:a\s+las\s+|hora\s*:?\s*)(\d{1,2}):(\d{2})\s*(a\.?m\.?|p\.?m\.?)?',
        caseSensitive: false);

int _normalizeYear(int year) => year >= 100 ? year : 2000 + year;

/// Extracts the payment instant from [text], using [receivedAt] to fill in
/// whatever the message left out.
///
/// Returns null when the message carries no timestamp, or when the timestamp
/// it carries is more than two days away from [receivedAt] — that is almost
/// always a due date or a statement date rather than the payment instant.
DateTime? findOccurredAt(String text, DateTime receivedAt) {
  DateTime? candidate;

  final ymd = _ymdPattern.firstMatch(text);
  if (ymd != null) {
    candidate = _build(
      year: int.parse(ymd.group(1)!),
      month: int.parse(ymd.group(2)!),
      day: int.parse(ymd.group(3)!),
      hour: ymd.group(4),
      minute: ymd.group(5),
      second: ymd.group(6),
      fallback: receivedAt,
    );
  }

  if (candidate == null) {
    final dmy = _dmyPattern.firstMatch(text);
    if (dmy != null) {
      candidate = _build(
        year: _normalizeYear(int.parse(dmy.group(3)!)),
        month: int.parse(dmy.group(2)!),
        day: int.parse(dmy.group(1)!),
        hour: dmy.group(4),
        minute: dmy.group(5),
        second: dmy.group(6),
        fallback: receivedAt,
      );
    }
  }

  if (candidate == null) {
    final textual = _textualDatePattern.firstMatch(text);
    if (textual != null) {
      final month = _monthAbbreviations[textual.group(2)!.toLowerCase()];
      if (month != null) {
        final yearGroup = textual.group(3);
        candidate = _build(
          year: yearGroup == null
              ? receivedAt.year
              : _normalizeYear(int.parse(yearGroup)),
          month: month,
          day: int.parse(textual.group(1)!),
          hour: textual.group(4),
          minute: textual.group(5),
          second: null,
          fallback: receivedAt,
        );
      }
    }
  }

  if (candidate == null) {
    // No date, but maybe a bare time: keep the arrival day, take the time.
    final timeOnly = _timeOnlyPattern.firstMatch(text);
    if (timeOnly != null) {
      var hour = int.parse(timeOnly.group(1)!);
      final minute = int.parse(timeOnly.group(2)!);
      final meridiem = timeOnly.group(3)?.replaceAll('.', '').toLowerCase();
      if (meridiem == 'pm' && hour < 12) hour += 12;
      if (meridiem == 'am' && hour == 12) hour = 0;
      if (hour > 23 || minute > 59) return null;
      candidate = DateTime(
          receivedAt.year, receivedAt.month, receivedAt.day, hour, minute);
    }
  }

  if (candidate == null) return null;
  if (candidate.difference(receivedAt).abs() > const Duration(days: 2)) {
    return null;
  }
  return candidate;
}

DateTime? _build({
  required int year,
  required int month,
  required int day,
  required String? hour,
  required String? minute,
  required String? second,
  required DateTime fallback,
}) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final h = hour == null ? 0 : int.tryParse(hour) ?? 0;
  final m = minute == null ? 0 : int.tryParse(minute) ?? 0;
  final s = second == null ? 0 : int.tryParse(second) ?? 0;
  if (h > 23 || m > 59 || s > 59) return null;
  final built = DateTime(year, month, day, h, m, s);
  // DateTime rolls overflow silently (Feb 31 → Mar 3); reject that.
  if (built.day != day || built.month != month) return null;
  return built;
}

/// Everything that can end a merchant name.
final _merchantTerminator = RegExp(
  r'\s+\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}'          // a date
  r'|\s*[,;:\n]'                                    // punctuation
  r'|\.\s'                                          // end of sentence
  r'|\s+(?:con|desde|hacia|para|tarjeta|producto|t\.?\s*(?:credito|debito)'
  r'|saldo|tu\s+saldo|su\s+saldo|el\s+dia|a\s+las|hora|ref\.?|referencia'
  r'|aprobad[oa]|exitos[oa]|valor|por\s+valor|cuota|cuotas|nro|numero'
  r'|inquietudes|dudas|si\s+no|no\s+fuiste)\b',
  caseSensitive: false,
);

/// Nouns that introduce a transfer destination. Lowercase; matched against
/// the normalised candidate.
const _destinationNouns = {
  'llave', 'cuenta', 'producto', 'nequi', 'daviplata', 'celular', 'numero',
  'nit', 'cc', 'ahorros', 'corriente',
};

/// Words that mark the account as the USER'S OWN, never the counterparty
/// ("desde tu cuenta *1951").
final _ownershipWord = RegExp(r'^(?:tu|tus|su|sus|mi|mis)\b');

final _leadingArticle = RegExp(r'^(?:el|la|los|las|lo)\s+');

/// A connector the terminator leaves dangling. Issuers write
/// "… a EDISON ARANGO CORREA el 20/09/26", and the cut lands before the date,
/// so the "el" stays glued to the name.
final _trailingConnector =
    RegExp(r'\s+(?:el|del|la|de|a|en|dia)$', caseSensitive: false);

enum _CounterpartyKind { name, identifier }

/// Pulls the counterparty out of [text].
///
/// Purchases name the merchant after "en"; transfers name the destination
/// after "a" (outgoing) or "de" (incoming). We search the text that FOLLOWS
/// the amount first, because the leading part is boilerplate ("Bancolombia le
/// informa").
///
/// Two things this has to get right for Colombian transfers, where most
/// payments have no shop name at all:
///
///   * **Every** occurrence of a preposition is considered, not just the
///     first. "a la llave 98648320 … a EDISON ARANGO CORREA" names the person
///     second, and they are the useful identity.
///   * A destination noun and its article are stripped down to the identifier
///     behind them, so "a la cuenta *01768288204" becomes
///     "CUENTA 01768288204" — something stable to hang an alias on. Without
///     this the whole candidate was discarded for starting with "la", and the
///     transfer arrived with no merchant to name.
///
/// A person's name outranks a bare identifier when a message carries both.
String? findMerchant(String text, int searchFrom, MessageKind kind) {
  final tail = searchFrom < text.length ? text.substring(searchFrom) : '';
  final prepositions = switch (kind) {
    MessageKind.transferIn => ['de', 'por parte de', 'en'],
    MessageKind.transferOut => ['a', 'en', 'hacia', 'para'],
    MessageKind.payment => ['a', 'de', 'en'],
    _ => ['en', 'a'],
  };

  String? firstIdentifier;

  for (final source in [tail, text]) {
    for (final preposition in prepositions) {
      // Matches only the preposition, never the text after it. A greedy `.+`
      // capture would swallow the rest of the message, leaving allMatches
      // with a single hit and hiding every later occurrence — which is how
      // "a EDISON ARANGO CORREA" stayed invisible behind "a la llave …".
      final pattern = RegExp(
        '(?:^|\\s)$preposition\\s+',
        caseSensitive: false,
      );

      for (final match in pattern.allMatches(source)) {
        final parsed = _classifyCounterparty(source.substring(match.end));
        if (parsed == null) continue;
        if (parsed.kind == _CounterpartyKind.name) return parsed.value;
        firstIdentifier ??= parsed.value;
      }
    }
  }

  return firstIdentifier;
}

/// Turns the text after a preposition into a counterparty, or null when it is
/// not one (the user's own account, a bare reference, boilerplate).
({_CounterpartyKind kind, String value})? _classifyCounterparty(String rest) {
  var candidate = rest;
  final terminator = _merchantTerminator.firstMatch(candidate);
  if (terminator != null) {
    candidate = candidate.substring(0, terminator.start);
  }
  candidate = candidate.trim();
  while (_trailingConnector.hasMatch(candidate)) {
    candidate = candidate.replaceFirst(_trailingConnector, '').trim();
  }
  if (candidate.length < 2) return null;

  var normalized = normalizeForMatch(candidate);
  if (normalized.isEmpty) return null;

  // "desde tu cuenta *1951" — the source, not the destination.
  if (_ownershipWord.hasMatch(normalized)) return null;

  normalized = normalized.replaceFirst(_leadingArticle, '');
  if (normalized.isEmpty) return null;

  final words = normalized.split(' ');
  if (_destinationNouns.contains(words.first) && words.length > 1) {
    // Keep the identifier, drop the punctuation issuers decorate it with.
    final id = words[1].replaceAll(RegExp(r'[^0-9a-z]'), '');
    if (id.isEmpty) return null;
    return (
      kind: _CounterpartyKind.identifier,
      value: '${words.first} $id'.toUpperCase(),
    );
  }

  // A bare number or reference is not a name.
  if (RegExp(r'^[\d\s*#.:-]+$').hasMatch(normalized)) return null;

  // Re-cut the original text to the same length so the raw casing survives.
  final articleLength = candidate.length - normalized.length;
  final raw = articleLength > 0 && articleLength < candidate.length
      ? candidate.substring(articleLength).trim()
      : candidate;
  return (kind: _CounterpartyKind.name, value: raw.isEmpty ? candidate : raw);
}

// ─── entry point ─────────────────────────────────────────────────────────────

class ExpenseMessageParser {
  const ExpenseMessageParser();

  /// Parses one captured message.
  ///
  /// [pinnedIssuer] is `capture_sources.issuer_key` — the issuer the user
  /// assigned to this source, which overrides detection.
  ParsedMessage parse({
    required String sourceKey,
    String title = '',
    required String body,
    required DateTime receivedAt,
    String? pinnedIssuer,
  }) {
    final combined = [title, body].where((s) => s.isNotEmpty).join(' — ');
    final normalized = normalizeForMatch(combined);

    final issuerKey = resolveIssuer(
      pinned: pinnedIssuer,
      sourceKey: sourceKey,
      title: title,
      body: body,
    );

    for (final (phrase, reason) in _ignoreRules) {
      if (normalized.contains(phrase)) {
        return ParsedMessage(
          status: ParseStatus.ignored,
          occurredAt: receivedAt,
          issuerKey: issuerKey,
          ignoredReason: reason,
        );
      }
    }

    MessageKind? kind;
    for (final (phrase, candidate) in _kindRules) {
      if (normalized.contains(phrase)) {
        kind = candidate;
        break;
      }
    }

    final amount = findAmount(combined);

    if (kind == null || amount == null) {
      return ParsedMessage(
        status: ParseStatus.unparsed,
        occurredAt: receivedAt,
        issuerKey: issuerKey,
        kind: kind,
        amount: amount?.value,
        currency: amount?.currency,
      );
    }

    final merchantRaw = findMerchant(combined, amount.end, kind);
    final merchantKey =
        merchantRaw == null ? null : normalizeMerchant(merchantRaw);
    final last4 = findCardLast4(combined);
    final occurredAt = findOccurredAt(combined, receivedAt);

    // Currency: an explicit marker on the number wins; otherwise infer from
    // wording ("10 dolares") and default to COP.
    final currency = amount.currency == 'USD'
        ? 'USD'
        : inferCurrency(normalized);

    // Base plus a point per corroborating signal. A fully-formed alert
    // (known bank, merchant, card, timestamp) lands around 0.95; a bare
    // "compra por $X" lands around 0.65, below the auto-post threshold, so it
    // gets reviewed instead of guessed at.
    var confidence = 0.45;
    if (issuerKey != null) confidence += 0.15;
    if (merchantKey != null && merchantKey.isNotEmpty) confidence += 0.15;
    if (last4 != null) confidence += 0.08;
    if (occurredAt != null) confidence += 0.07;
    // A well-formed purchase/withdrawal line is the shape we understand best.
    if (kind == MessageKind.purchase || kind == MessageKind.withdrawal) {
      confidence += 0.05;
    }
    confidence = confidence.clamp(0.0, 1.0);

    return ParsedMessage(
      status: ParseStatus.parsed,
      kind: kind,
      issuerKey: issuerKey,
      amount: amount.value,
      currency: currency,
      merchantRaw: merchantRaw,
      merchantKey: (merchantKey?.isEmpty ?? true) ? null : merchantKey,
      cardLast4: last4,
      occurredAt: occurredAt ?? receivedAt,
      confidence: double.parse(confidence.toStringAsFixed(3)),
    );
  }
}
