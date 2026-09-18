import 'package:flutter/foundation.dart';

import 'package:budgett_frontend/core/parsing/expense_message_parser.dart';
import 'package:budgett_frontend/core/parsing/message_kind.dart';
import 'package:budgett_frontend/core/parsing/text_normalizer.dart';
import 'package:budgett_frontend/core/services/message_capture_service.dart';
import 'package:budgett_frontend/core/utils/capture_dedup.dart';
import 'package:budgett_frontend/core/utils/credit_card_calculator.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/bank_model.dart';
import 'package:budgett_frontend/data/models/capture_source_model.dart';
import 'package:budgett_frontend/data/models/captured_message_model.dart';
import 'package:budgett_frontend/data/models/merchant_alias_model.dart';
import 'package:budgett_frontend/data/repositories/finance_repository.dart';
import 'package:budgett_frontend/data/repositories/message_capture_repository.dart';

/// Knobs for the hybrid behaviour: how sure the pipeline has to be before it
/// records an expense on its own.
class CaptureSettings {
  /// Master switch for unattended posting. Off = everything waits in the inbox.
  final bool autoPostEnabled;

  /// How far apart two copies of the same payment can arrive.
  final Duration dedupWindow;

  /// Minimum parser confidence for unattended posting.
  final double minConfidence;

  /// Safety cap: amounts above this always get reviewed. 0 = no cap.
  final double autoPostMaxAmount;

  const CaptureSettings({
    this.autoPostEnabled = true,
    this.dedupWindow = kDefaultDedupWindow,
    this.minConfidence = 0.8,
    this.autoPostMaxAmount = 0,
  });

  CaptureSettings copyWith({
    bool? autoPostEnabled,
    Duration? dedupWindow,
    double? minConfidence,
    double? autoPostMaxAmount,
  }) =>
      CaptureSettings(
        autoPostEnabled: autoPostEnabled ?? this.autoPostEnabled,
        dedupWindow: dedupWindow ?? this.dedupWindow,
        minConfidence: minConfidence ?? this.minConfidence,
        autoPostMaxAmount: autoPostMaxAmount ?? this.autoPostMaxAmount,
      );
}

class CaptureIngestResult {
  final int inserted;
  final int posted;
  final int pending;
  final int duplicates;
  final int ignored;
  final int skippedDisabledSource;
  final List<String> errors;

  const CaptureIngestResult({
    this.inserted = 0,
    this.posted = 0,
    this.pending = 0,
    this.duplicates = 0,
    this.ignored = 0,
    this.skippedDisabledSource = 0,
    this.errors = const [],
  });

  bool get isEmpty => inserted == 0 && errors.isEmpty;

  /// One-line summary for the snackbar shown after a manual sync.
  String get summary {
    if (inserted == 0) return 'No new messages';
    final parts = <String>[
      if (posted > 0) '$posted recorded',
      if (pending > 0) '$pending to review',
      if (duplicates > 0) '$duplicates duplicate${duplicates == 1 ? '' : 's'}',
    ];
    if (parts.isEmpty) return '$inserted message${inserted == 1 ? '' : 's'} captured';
    return parts.join(' · ');
  }
}

/// Drains the native queue and turns each message into either a transaction or
/// an inbox item.
///
/// The order of operations matters:
///
///   1. **Source first.** A message from a source the user switched off is
///      dropped before it is stored anywhere.
///   2. **Parse, then classify.** The parser says what happened; the user's
///      aliases say how to file it.
///   3. **Dedup before posting**, against messages already stored, messages
///      earlier in this same batch, and transactions entered by hand.
///   4. **Post only when every question is already answered** — known account,
///      a learned alias with a category, high confidence, no duplicate. Anything
///      else lands in the inbox, which is also how the pipeline learns: the
///      first time a merchant is confirmed, an alias is written, and the next
///      message from that merchant posts by itself.
class CaptureIngestService {
  final MessageCaptureRepository captureRepo;
  final FinanceRepository financeRepo;
  final CapturePlatform platform;
  final ExpenseMessageParser parser;

  CaptureIngestService({
    required this.captureRepo,
    required this.financeRepo,
    CapturePlatform? platform,
    this.parser = const ExpenseMessageParser(),
  }) : platform = platform ?? MessageCaptureService();

  /// Drains the queue and processes everything in it.
  ///
  /// [accounts] and [banks] are passed in rather than fetched so the caller's
  /// already-loaded provider data is reused; credit-card billing fields need
  /// both.
  Future<CaptureIngestResult> ingest({
    required List<Account> accounts,
    required List<Bank> banks,
    CaptureSettings settings = const CaptureSettings(),
  }) async {
    final raw = await platform.drain();
    if (raw.isEmpty) return const CaptureIngestResult();

    // Oldest first, so the earliest copy of a payment becomes the original and
    // later copies are the ones marked as duplicates.
    raw.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

    final known = await captureRepo.knownFingerprints();
    final aliases = await captureRepo.getAliases();
    final cardMap = await captureRepo.getCardMappings();

    final accountsById = {
      for (final account in _flatten(accounts)) account.id: account
    };
    final banksById = {for (final bank in banks) bank.id: bank};

    // Sources are cached per batch: a push and an SMS about the same payment
    // arrive together and would otherwise hit the same row twice.
    final sourceCache = <String, CaptureSource>{};

    var inserted = 0;
    var posted = 0;
    var pending = 0;
    var duplicates = 0;
    var ignored = 0;
    var skipped = 0;
    final errors = <String>[];

    // Copies inserted during this batch, so two sources in one drain
    // deduplicate against each other.
    final batchCandidates = <DedupCandidate>[];

    for (final capture in raw) {
      if (known.contains(capture.fingerprint)) continue;
      known.add(capture.fingerprint);

      try {
        final cacheKey = '${capture.channel}|${capture.sourceKey}';
        final source = sourceCache[cacheKey] ??= await captureRepo.registerSource(
          channel: capture.channel,
          sourceKey: capture.sourceKey,
          detectedName: capture.sourceName,
          seenAt: capture.receivedAt,
        );

        if (!source.isEnabled) {
          skipped++;
          continue;
        }

        final parsed = parser.parse(
          sourceKey: capture.sourceKey,
          title: capture.title ?? '',
          body: capture.body,
          receivedAt: capture.receivedAt,
          pinnedIssuer: source.issuerKey,
        );

        final outcome = await _process(
          capture: capture,
          source: source,
          parsed: parsed,
          aliases: aliases,
          cardMap: cardMap,
          accountsById: accountsById,
          banksById: banksById,
          settings: settings,
          batchCandidates: batchCandidates,
        );

        inserted++;
        switch (outcome) {
          case _Outcome.posted:
            posted++;
          case _Outcome.pending:
            pending++;
          case _Outcome.duplicate:
            duplicates++;
          case _Outcome.ignored:
            ignored++;
        }
      } catch (e) {
        debugPrint('Capture ingest failed for ${capture.sourceKey}: $e');
        errors.add('${capture.sourceKey}: $e');
      }
    }

    return CaptureIngestResult(
      inserted: inserted,
      posted: posted,
      pending: pending,
      duplicates: duplicates,
      ignored: ignored,
      skippedDisabledSource: skipped,
      errors: errors,
    );
  }

  Future<_Outcome> _process({
    required RawCapture capture,
    required CaptureSource source,
    required ParsedMessage parsed,
    required List<MerchantAlias> aliases,
    required Map<String, String> cardMap,
    required Map<String, Account> accountsById,
    required Map<String, Bank> banksById,
    required CaptureSettings settings,
    required List<DedupCandidate> batchCandidates,
  }) async {
    final locationLabel = await _describeLocation(capture);

    final base = <String, dynamic>{
      'source_id': source.id,
      'channel': capture.channel,
      'source_key': capture.sourceKey,
      'title': capture.title,
      'body': capture.body,
      'received_at': capture.receivedAt.toUtc().toIso8601String(),
      'occurred_at': parsed.occurredAt.toUtc().toIso8601String(),
      'latitude': capture.latitude,
      'longitude': capture.longitude,
      'location_accuracy_m': capture.locationAccuracyM,
      'location_label': locationLabel,
      'parse_status': parsed.status.wireName,
      'issuer_key': parsed.issuerKey,
      'fingerprint': capture.fingerprint,
    };

    // Not a movement: stored for the record, kept out of the inbox.
    if (parsed.status == ParseStatus.ignored) {
      await captureRepo.insertCapture({
        ...base,
        'status': 'dismissed',
        'error': parsed.ignoredReason,
      });
      return _Outcome.ignored;
    }

    // Looks financial but unreadable — worth showing so the user can enter it
    // by hand, and so a parser gap is visible instead of silent.
    if (!parsed.isUsable) {
      await captureRepo.insertCapture({
        ...base,
        'amount': parsed.amount,
        'currency': parsed.currency,
        'kind': parsed.kind?.wireName,
        'status': 'pending',
      });
      return _Outcome.pending;
    }

    // A rejected attempt moved no money.
    if (parsed.kind == MessageKind.declined) {
      await captureRepo.insertCapture({
        ...base,
        'amount': parsed.amount,
        'currency': parsed.currency,
        'merchant_raw': parsed.merchantRaw,
        'card_last4': parsed.cardLast4,
        'kind': parsed.kind!.wireName,
        'confidence': parsed.confidence,
        'status': 'dismissed',
        'error': 'Declined by the bank',
      });
      return _Outcome.ignored;
    }

    final alias = MerchantAlias.bestMatch(aliases, parsed.merchantKey);
    final merchantDisplay = alias?.displayName ??
        MerchantAlias.suggestDisplayName(parsed.merchantRaw, parsed.merchantKey);

    final accountId = _resolveAccount(
      alias: alias,
      parsed: parsed,
      source: source,
      cardMap: cardMap,
      accountsById: accountsById,
    );

    final candidate = DedupCandidate(
      id: capture.fingerprint,
      amount: parsed.amount!,
      currency: parsed.currency ?? 'COP',
      merchantKey: parsed.merchantKey,
      cardLast4: parsed.cardLast4,
      issuerKey: parsed.issuerKey,
      occurredAt: parsed.occurredAt,
    );

    final stored = await captureRepo.capturesNear(parsed.occurredAt);
    final existing = [
      ...stored.map((m) => m.toDedupCandidate(
            merchantKey: m.merchantRaw == null
                ? null
                : normalizeMerchant(m.merchantRaw!),
          )),
      ...batchCandidates,
    ];

    final duplicate = findDuplicateCapture(
      candidate,
      existing,
      window: settings.dedupWindow,
    );

    final row = <String, dynamic>{
      ...base,
      'amount': parsed.amount,
      'currency': parsed.currency,
      'merchant_raw': parsed.merchantRaw,
      'merchant_display': merchantDisplay,
      'card_last4': parsed.cardLast4,
      'kind': parsed.kind!.wireName,
      'confidence': parsed.confidence,
      'matched_alias_id': alias?.id,
      'dedup_hash': dedupHash(
        amount: parsed.amount!,
        currency: parsed.currency ?? 'COP',
        merchantKey: parsed.merchantKey,
        cardLast4: parsed.cardLast4,
      ),
    };

    if (duplicate != null && duplicate.isConclusive) {
      // duplicate_of only accepts a stored row id; a same-batch match is
      // identified by fingerprint, which is not a uuid, so it is recorded in
      // `error` instead of pointing at nothing.
      final matchIsStored = stored.any((m) => m.id == duplicate.matchId);
      final message = await captureRepo.insertCapture({
        ...row,
        'status': 'duplicate',
        if (matchIsStored) 'duplicate_of': duplicate.matchId,
        'error': duplicate.reason.label,
      });
      batchCandidates.add(candidate);
      debugPrint('Capture ${message.id} filed as duplicate: '
          '${duplicate.reason.label}');
      return _Outcome.duplicate;
    }

    // A weak duplicate signal, or a collision with something already recorded
    // by hand, does not hide the message — it just takes auto-posting off the
    // table and shows up as a warning in the inbox.
    final collision = duplicate ??
        findTransactionCollision(
          candidate,
          await captureRepo.transactionsNear(
            day: parsed.occurredAt,
            amount: parsed.amount!,
            currency: parsed.currency ?? 'COP',
          ),
          window: settings.dedupWindow,
        );

    final canPost = _canAutoPost(
      parsed: parsed,
      alias: alias,
      accountId: accountId,
      collision: collision,
      settings: settings,
    );

    final message = await captureRepo.insertCapture({
      ...row,
      'status': 'pending',
      if (collision != null) 'error': collision.reason.label,
    });
    batchCandidates.add(candidate);

    if (!canPost) return _Outcome.pending;

    try {
      final transactionId = await postTransaction(
        message: message,
        parsed: parsed,
        accountId: accountId!,
        merchantDisplay: merchantDisplay,
        categoryId: alias!.categoryId,
        subCategoryId: alias.subCategoryId,
        expenseGroupId: alias.expenseGroupId,
        movementType: alias.movementType ?? parsed.kind!.movementType,
        sourceName: source.effectiveName,
        accountsById: accountsById,
        banksById: banksById,
      );

      await captureRepo.updateCapture(message.id, {
        'status': 'posted',
        'transaction_id': transactionId,
      });
      await captureRepo.touchAlias(alias.id, alias.hitCount);
      return _Outcome.posted;
    } catch (e) {
      // The message stays pending so the expense is not lost; the error is
      // visible in the inbox.
      await captureRepo.updateCapture(message.id, {
        'status': 'pending',
        'error': 'Could not record automatically: $e',
      });
      return _Outcome.pending;
    }
  }

  /// Builds and inserts the transaction for [message]. Public so the inbox can
  /// reuse the exact same payload shape when the user confirms by hand.
  Future<String> postTransaction({
    required CapturedMessage message,
    required ParsedMessage parsed,
    required String accountId,
    required String merchantDisplay,
    String? categoryId,
    String? subCategoryId,
    String? expenseGroupId,
    String? movementType,
    String? targetAccountId,
    String? sourceName,
    required Map<String, Account> accountsById,
    required Map<String, Bank> banksById,
  }) async {
    final kind = parsed.kind ?? MessageKind.purchase;
    final occurredAt = parsed.occurredAt;

    final data = <String, dynamic>{
      'account_id': accountId,
      'amount': parsed.amount,
      'description': merchantDisplay,
      'date': occurredAt.toIso8601String().split('T')[0],
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'type': kind.transactionType,
      'status': 'paid',
      'currency': parsed.currency ?? 'COP',
      'place': merchantDisplay,
      'movement_type': movementType ?? kind.movementType,
      'auto_captured': true,
      'captured_message_id': message.id,
      if (categoryId != null) 'category_id': categoryId,
      if (subCategoryId != null) 'sub_category_id': subCategoryId,
      if (categoryId != null && expenseGroupId != null)
        'expense_group_id': expenseGroupId,
      if (targetAccountId != null) 'target_account_id': targetAccountId,
      if (message.latitude != null) 'latitude': message.latitude,
      if (message.longitude != null) 'longitude': message.longitude,
      if (message.locationLabel != null)
        'location_label': message.locationLabel,
      'notes': _buildNotes(message, parsed, sourceName),
    };

    // Credit-card purchases must land in the right statement cycle, exactly as
    // the manual dialog computes it.
    final account = accountsById[accountId];
    final rules = account?.creditCardRules;
    if (account?.type == 'credit_card' && rules != null) {
      final bank = banksById[rules.bankId];
      if (bank != null) {
        try {
          data.addAll(CreditCardCalculator.billingFieldsFor(
            date: occurredAt,
            rules: rules,
            bank: bank,
          ));
        } catch (e) {
          debugPrint('Could not derive billing fields for $accountId: $e');
        }
      }
    }

    return financeRepo.addTransactionWithReturn(data);
  }

  String _buildNotes(
      CapturedMessage message, ParsedMessage parsed, String? sourceName) {
    final parts = <String>[
      'Auto-captured from ${sourceName ?? message.sourceKey}',
      if (parsed.cardLast4 != null) 'card •${parsed.cardLast4}',
      if (message.locationLabel != null) message.locationLabel!,
    ];
    return parts.join(' · ');
  }

  /// Account resolution, most specific signal first: the alias pins one, the
  /// card's last four digits map to one, or the source has a default.
  String? _resolveAccount({
    required MerchantAlias? alias,
    required ParsedMessage parsed,
    required CaptureSource source,
    required Map<String, String> cardMap,
    required Map<String, Account> accountsById,
  }) {
    final last4 = parsed.cardLast4;
    final candidates = <String?>[
      alias?.accountId,
      if (last4 != null) ...[
        // This bank's card first, then a mapping that applies to any bank.
        cardMap['${parsed.issuerKey ?? ''}|$last4'],
        cardMap['|$last4'],
      ],
      source.defaultAccountId,
    ];
    for (final id in candidates) {
      if (id != null && accountsById.containsKey(id)) return id;
    }
    return null;
  }

  /// Every condition that must hold for a message to be recorded unattended.
  ///
  /// The alias requirement is what makes this self-teaching: a merchant is
  /// always reviewed once, and only then does it start posting on its own.
  bool _canAutoPost({
    required ParsedMessage parsed,
    required MerchantAlias? alias,
    required String? accountId,
    required DuplicateVerdict? collision,
    required CaptureSettings settings,
  }) {
    if (!settings.autoPostEnabled) return false;
    if (collision != null) return false;
    if (accountId == null) return false;
    if (alias == null || !alias.autoPost || !alias.isComplete) return false;
    if (parsed.kind == null || !parsed.kind!.isAutoPostable) return false;
    if (parsed.confidence < settings.minConfidence) return false;
    if (settings.autoPostMaxAmount > 0 &&
        (parsed.amount ?? 0) > settings.autoPostMaxAmount) {
      return false;
    }
    return true;
  }

  Future<String?> _describeLocation(RawCapture capture) async {
    if (capture.latitude == null || capture.longitude == null) return null;
    return platform.describeLocation(capture.latitude!, capture.longitude!);
  }

  /// Flattens parent accounts and their pockets — a card last-4 can belong to
  /// either.
  List<Account> _flatten(List<Account> accounts) => [
        for (final account in accounts) ...[account, ...account.pockets]
      ];
}

enum _Outcome { posted, pending, duplicate, ignored }
