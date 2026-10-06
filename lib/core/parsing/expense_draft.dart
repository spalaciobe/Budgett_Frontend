/// What a photo or a spoken phrase turns into before the user confirms it.
///
/// This is deliberately the same shape the message parser produces, because
/// it ends up in the same review sheet. Nothing here is ever written without
/// confirmation: a receipt can be blurry and a microphone can mishear, and
/// unlike a bank alert there is no issuer vouching for the numbers.
library;

import 'package:budgett_frontend/core/parsing/message_kind.dart';

/// Where a draft came from, which is what the review sheet shows and what
/// decides how much of it can be trusted.
enum DraftSource {
  /// Text read off a photographed receipt.
  receipt,

  /// A phrase the user spoke.
  voice,
}

class ExpenseDraft {
  final DraftSource source;

  /// Null when nothing in the input looked like money — the one field with no
  /// sensible fallback, so the UI must ask for it.
  final double? amount;
  final String currency;

  /// The merchant, or whatever the user said they spent it on. Becomes
  /// `place`, and the alias key, exactly as a captured message's merchant
  /// does — so a receipt from a shop the user has already taught picks up
  /// that rule.
  final String? merchant;

  /// A free-text note for this one expense, kept apart from [merchant] for
  /// the same reason the review sheet keeps them apart: "Desayuno con Ana" is
  /// about this purchase, "D1 Sabaneta" is about every purchase there.
  final String? description;

  final MessageKind kind;

  /// The account the user named out loud ("… a Bancolombia"), when exactly
  /// one of theirs matches. Null when nothing was said or when more than one
  /// account could have been meant — picking the wrong one puts real money
  /// against the wrong balance.
  final String? accountId;

  /// The day the money moved. Falls back to now when the input gives nothing.
  final DateTime date;

  /// 0–1. Below [kDraftReviewThreshold] the UI should highlight the fields
  /// rather than present the draft as a finished answer.
  final double confidence;

  /// What the extractor actually read, kept so the user can see where a wrong
  /// number came from instead of having to guess.
  final String rawText;

  /// Set when a field was recognised but not understood, so the sheet can say
  /// so rather than silently leaving a blank.
  final String? warning;

  const ExpenseDraft({
    required this.source,
    required this.amount,
    this.currency = 'COP',
    this.merchant,
    this.description,
    this.kind = MessageKind.purchase,
    this.accountId,
    required this.date,
    required this.confidence,
    required this.rawText,
    this.warning,
  });

  bool get isUsable => amount != null && amount! > 0;

  ExpenseDraft copyWith({
    double? amount,
    String? currency,
    String? merchant,
    String? description,
    MessageKind? kind,
    String? accountId,
    DateTime? date,
    double? confidence,
    String? warning,
  }) =>
      ExpenseDraft(
        source: source,
        amount: amount ?? this.amount,
        currency: currency ?? this.currency,
        merchant: merchant ?? this.merchant,
        description: description ?? this.description,
        kind: kind ?? this.kind,
        accountId: accountId ?? this.accountId,
        date: date ?? this.date,
        confidence: confidence ?? this.confidence,
        rawText: rawText,
        warning: warning ?? this.warning,
      );

  @override
  String toString() => 'ExpenseDraft(${kind.name} $amount $currency '
      'merchant=$merchant conf=${confidence.toStringAsFixed(2)})';
}

/// Below this, the draft is a suggestion rather than an answer.
///
/// Lower than the 0.8 a bank message must clear to post itself, because a
/// draft never posts itself: a human is looking at it either way, and the
/// threshold only decides how loudly the UI doubts itself.
const kDraftReviewThreshold = 0.6;
