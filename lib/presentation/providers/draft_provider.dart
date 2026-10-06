/// Turns a photo or a spoken phrase into drafts, ready for review.
///
/// The order here is the whole design: read the text on the device, let the
/// rules understand it, and only call the local model for what they could not
/// read. The model never runs on a draft the rules were sure of, which keeps
/// the common case instant and free.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:budgett_frontend/core/parsing/expense_draft.dart';
import 'package:budgett_frontend/core/parsing/llm_draft_extractor.dart';
import 'package:budgett_frontend/core/parsing/receipt_parser.dart';
import 'package:budgett_frontend/core/parsing/screenshot_parser.dart';
import 'package:budgett_frontend/core/parsing/voice_expense_parser.dart';
import 'package:budgett_frontend/core/services/draft_capture_service.dart';
import 'package:budgett_frontend/core/services/local_llm_service.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';

final draftCaptureServiceProvider =
    Provider<DraftCaptureService>((ref) => const DraftCaptureService());

final localLlmServiceProvider =
    Provider<LocalLlmService>((ref) => const LocalLlmService());

/// Whether a local model is installed right now.
final localModelInstalledProvider = FutureProvider<bool>(
    (ref) => ref.watch(localLlmServiceProvider).isInstalled());

/// Bytes the installed model occupies, for the settings screen.
final localModelSizeProvider = FutureProvider<int>(
    (ref) => ref.watch(localLlmServiceProvider).installedSize());

/// Whether the phone can dictate — the recogniser exists and the microphone
/// is already granted.
final canDictateProvider = FutureProvider<bool>(
    (ref) => ref.watch(draftCaptureServiceProvider).canDictate());

/// Reads an image into drafts.
///
/// One image can hold several movements, so this returns a list. A photo of a
/// bank app is far more common than a photo of a paper receipt, so the
/// screenshot reading is tried first and the receipt reading is the fallback
/// — the other way round, a statement list collapses into one wrong total.
final draftsFromImageProvider =
    FutureProvider.family<List<ExpenseDraft>, String>((ref, path) async {
  final capture = ref.read(draftCaptureServiceProvider);
  final text = await capture.readImage(path);
  if (text.trim().isEmpty) return const [];

  final now = DateTime.now();
  var drafts = parseScreenshot(text, capturedAt: now);

  // Nothing that looked like a movements list or a confirmation screen: this
  // is a paper receipt.
  if (drafts.isEmpty || !drafts.any((d) => d.isUsable)) {
    final receipt = parseReceipt(text, capturedAt: now);
    if (receipt.isUsable || drafts.isEmpty) drafts = [receipt];
  }

  return _completeAll(drafts, ref);
});

/// Listens for a phrase and reads it.
///
/// Exposed as a provider rather than a bare function so a widget can reach it
/// with the `WidgetRef` it already has.
final dictateDraftProvider = Provider<Future<ExpenseDraft> Function()>(
    (ref) => () => _dictateDraft(ref));

Future<ExpenseDraft> _dictateDraft(Ref ref) async {
  final capture = ref.read(draftCaptureServiceProvider);
  final heard = await capture.dictate();
  if (heard.trim().isEmpty) {
    throw const DraftCaptureException('Nothing was heard — try again');
  }
  // The user's accounts, so "… a Bancolombia" selects one. Read rather than
  // watched: this runs once, in response to a button.
  final accounts = await ref.read(accountsProvider.future);
  final draft = parseVoiceExpense(heard, accounts: _flatten(accounts));
  final completed = await _completeAll([draft], ref);
  return completed.single;
}

/// Accounts plus their pockets, since a bolsillo is nameable too.
List<Account> _flatten(List<Account> accounts) => [
      for (final account in accounts) ...[account, ...account.pockets],
    ];

/// Offers each unsure draft to the local model, one at a time.
///
/// Sequential on purpose: a phone runs one model at a time anyway, and three
/// parallel requests would queue behind each other while the UI pretended
/// otherwise.
Future<List<ExpenseDraft>> _completeAll(
    List<ExpenseDraft> drafts, Ref ref) async {
  final unsure = drafts.where(
      (d) => !d.isUsable || d.confidence < kDraftReviewThreshold);
  if (unsure.isEmpty) return drafts;

  final llm = ref.read(localLlmServiceProvider);
  if (!await llm.isInstalled()) return drafts;

  final out = <ExpenseDraft>[];
  for (final draft in drafts) {
    out.add(await completeWithModel(draft, llm: llm));
  }
  return out;
}
