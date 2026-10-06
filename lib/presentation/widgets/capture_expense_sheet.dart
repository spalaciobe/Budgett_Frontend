/// Entering an expense with the camera or the microphone.
///
/// Shows what was read before anything is saved. One image can hold several
/// movements — a screenshot of a movements list usually does — so the result
/// is a list of cards, and each one opens the ordinary add-transaction dialog
/// pre-filled. Nothing here writes to the ledger on its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';

import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/core/app_text.dart';
import 'package:budgett_frontend/core/parsing/expense_draft.dart';
import 'package:budgett_frontend/core/services/draft_capture_service.dart';
import 'package:budgett_frontend/presentation/providers/draft_provider.dart';
import 'package:budgett_frontend/presentation/widgets/add_transaction_dialog.dart';

/// Opens the capture sheet. [startWith] skips the chooser and goes straight
/// to the camera or the microphone, which is what the two shortcut buttons do.
Future<void> showCaptureExpenseSheet(
  BuildContext context, {
  CaptureMode? startWith,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CaptureExpenseSheet(startWith: startWith),
    );

/// How the expense is being entered.
enum CaptureMode { camera, gallery, voice }

class CaptureExpenseSheet extends ConsumerStatefulWidget {
  const CaptureExpenseSheet({
    super.key,
    this.startWith,
    this.initialDrafts = const [],
  });

  final CaptureMode? startWith;

  /// Drafts to show straight away, for a caller that already has them.
  final List<ExpenseDraft> initialDrafts;

  @override
  ConsumerState<CaptureExpenseSheet> createState() =>
      _CaptureExpenseSheetState();
}

class _CaptureExpenseSheetState extends ConsumerState<CaptureExpenseSheet> {
  bool _busy = false;
  bool _showRawText = false;
  String? _status;
  String? _error;
  late List<ExpenseDraft> _drafts = widget.initialDrafts;

  /// Drafts the user has already turned into transactions, so the list shows
  /// what is left rather than silently repeating itself.
  final _handled = <int>{};

  @override
  void initState() {
    super.initState();
    final start = widget.startWith;
    if (start != null) {
      // After the first frame: the sheet has to exist before the camera or
      // the permission dialog is put in front of it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(start));
    }
  }

  Future<void> _run(CaptureMode mode) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = mode == CaptureMode.voice ? 'Listening…' : 'Reading the image…';
    });

    try {
      final drafts = mode == CaptureMode.voice
          ? [await _dictate()]
          : await _fromImage(mode);

      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        _handled.clear();
        _error = drafts.isEmpty ? 'Nothing readable was found' : null;
      });
    } on DraftCaptureException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read that: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ExpenseDraft> _dictate() async {
    final capture = ref.read(draftCaptureServiceProvider);
    if (!await capture.canDictate()) {
      final granted = await capture.requestMicrophone();
      if (!granted) {
        throw const DraftCaptureException(
          'Dictation needs the microphone. You can allow it in Settings.',
        );
      }
    }
    return ref.read(dictateDraftProvider)();
  }

  Future<List<ExpenseDraft>> _fromImage(CaptureMode mode) async {
    final picked = await ImagePicker().pickImage(
      source:
          mode == CaptureMode.camera ? ImageSource.camera : ImageSource.gallery,
      // Enough for OCR without making a 12-megapixel file the model has to
      // wait on. Receipt print stays legible well below the sensor's size.
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (picked == null) return const [];

    if (mounted) setState(() => _status = 'Reading the image…');
    return ref.read(draftsFromImageProvider(picked.path).future);
  }

  Future<void> _confirm(int index) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AddTransactionDialog(draft: _drafts[index]),
    );
    if (!mounted) return;
    setState(() => _handled.add(index));

    // Everything dealt with: close rather than leaving an empty sheet.
    if (_handled.length == _drafts.length && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supported = ref.watch(draftCaptureServiceProvider).isSupported;

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: kSpaceLg,
            right: kSpaceLg,
            bottom: MediaQuery.of(context).viewInsets.bottom + kSpaceLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add from a photo or your voice',
                  style: theme.textTheme.titleLarge),
              kGapSm,
              Text(
                supported
                    ? 'Photograph a receipt or a screenshot of your bank app, '
                        'or just say what you spent.'
                    : 'This only works on Android.',
                style: AppText.caption,
              ),
              kGapLg,
              if (supported) _buildActions(),
              if (_busy) ...[
                kGapLg,
                const LinearProgressIndicator(),
                kGapSm,
                Text(_status ?? '', style: AppText.caption),
              ],
              if (_error != null) ...[
                kGapLg,
                _ErrorNote(message: _error!),
              ],
              if (_drafts.isNotEmpty) ...[
                kGapLg,
                const Divider(),
                kGapSm,
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _drafts.length == 1
                            ? 'Found one movement'
                            : 'Found ${_drafts.length} movements',
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    // What the camera actually read. A wrong figure is far
                    // easier to understand — and to report — when its source
                    // is one tap away instead of invisible.
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showRawText = !_showRawText),
                      icon: Icon(
                        _showRawText
                            ? Icons.expand_less
                            : Icons.text_snippet_outlined,
                        size: 18,
                      ),
                      label: const Text('Text read'),
                    ),
                  ],
                ),
                if (_showRawText) ...[
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(kSpaceMd),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(kCardRadius),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _drafts.first.rawText,
                        style: AppText.caption,
                      ),
                    ),
                  ),
                  kGapSm,
                ],
                kGapSm,
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _drafts.length,
                    separatorBuilder: (_, __) => kGapSm,
                    itemBuilder: (_, i) => _DraftCard(
                      draft: _drafts[i],
                      done: _handled.contains(i),
                      onTap: _busy ? null : () => _confirm(i),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions() => Row(
        children: [
          Expanded(
            child: _ActionButton(
              icon: Icons.photo_camera_outlined,
              label: 'Camera',
              onPressed: _busy ? null : () => _run(CaptureMode.camera),
            ),
          ),
          const SizedBox(width: kSpaceLg),
          Expanded(
            child: _ActionButton(
              icon: Icons.image_outlined,
              label: 'Gallery',
              onPressed: _busy ? null : () => _run(CaptureMode.gallery),
            ),
          ),
          const SizedBox(width: kSpaceLg),
          Expanded(
            child: _ActionButton(
              icon: Icons.mic_none_outlined,
              label: 'Speak',
              onPressed: _busy ? null : () => _run(CaptureMode.voice),
            ),
          ),
        ],
      );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: kSpaceMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            kGapXs,
            Text(label, style: AppText.caption, textAlign: TextAlign.center),
          ],
        ),
      );
}

/// One movement that was read, shown before it becomes anything.
class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.done,
    required this.onTap,
  });

  final ExpenseDraft draft;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        enabled: !done,
        onTap: done ? null : onTap,
        leading: Icon(
          done
              ? Icons.check_circle
              : draft.source == DraftSource.voice
                  ? Icons.mic_none_outlined
                  : Icons.receipt_long_outlined,
          color: done ? theme.colorScheme.primary : null,
        ),
        title: Text(
          draft.amount == null
              ? 'Amount not readable'
              : CurrencyFormatter.format(draft.amount!,
                  currency: draft.currency, decimalDigits: 0),
          style: AppText.subtitle,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                draft.merchant ?? draft.description ?? 'No name',
                DateFormat('d MMM', 'es_CO').format(draft.date),
                draft.kind.label,
              ].join(' · '),
              style: AppText.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (draft.warning != null) ...[
              kGapXs,
              Text(
                draft.warning!,
                style: AppText.caption.copyWith(color: theme.colorScheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: done ? null : const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(kSpaceMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: kSpaceLg),
          Expanded(
            child: Text(
              message,
              style: AppText.caption
                  .copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
