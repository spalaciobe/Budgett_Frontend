import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/core/app_text.dart';
import 'package:budgett_frontend/core/parsing/expense_message_parser.dart';
import 'package:budgett_frontend/core/parsing/issuer_registry.dart';
import 'package:budgett_frontend/core/parsing/message_kind.dart';
import 'package:budgett_frontend/core/parsing/text_normalizer.dart';
import 'package:budgett_frontend/core/utils/error_messages.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/captured_message_model.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/merchant_alias_model.dart';
import 'package:budgett_frontend/data/repositories/bank_repository.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/providers/message_capture_provider.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';

/// Confirms one captured message — and, more importantly, teaches the pipeline
/// what to do with the next one like it.
///
/// The three "Remember" switches at the bottom are the whole point: a merchant
/// confirmed once here becomes a `merchant_aliases` row, and the next message
/// from that merchant is recorded without ever reaching this screen.
class ReviewCaptureSheet extends ConsumerStatefulWidget {
  final CapturedMessage message;

  const ReviewCaptureSheet({super.key, required this.message});

  @override
  ConsumerState<ReviewCaptureSheet> createState() =>
      _ReviewCaptureSheetState();
}

class _ReviewCaptureSheetState extends ConsumerState<ReviewCaptureSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _nameController;

  late String _type;
  late String _currency;
  late DateTime _occurredAt;

  String? _accountId;
  String? _targetAccountId;
  String? _categorySelection; // category id OR sub-category id
  String? _expenseGroupId;

  bool _rememberName = true;
  bool _autoPostNext = true;
  bool _rememberCard = true;
  bool _showRawMessage = false;
  bool _saving = false;

  CapturedMessage get _message => widget.message;

  /// Alias key for this merchant. Null when the parser found no merchant, in
  /// which case there is nothing stable to remember the rule against.
  String? get _merchantKey => _message.merchantRaw == null
      ? null
      : normalizeMerchant(_message.merchantRaw!);

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _message.amount == null
          ? ''
          : CurrencyFormatter.format(
              _message.amount!,
              currency: _message.currency ?? 'COP',
              includeSymbol: false,
              decimalDigits: 0,
            ),
    );
    _nameController = TextEditingController(text: _message.headline);
    // The "Remember" subtitles quote the name, so they have to follow typing.
    _nameController.addListener(_onNameChanged);
    _type = _message.kind?.transactionType ?? 'expense';
    _currency = _message.currency ?? 'COP';
    _occurredAt = _message.occurredAt;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  List<Account> _flatten(List<Account> accounts) => [
        for (final account in accounts) ...[account, ...account.pockets]
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final expenseGroupsAsync = ref.watch(expenseGroupsProvider);

    // Seed the account once the list is available: the alias, the card map or
    // the source default may already have picked one during ingestion.
    final accounts = accountsAsync.valueOrNull ?? const <Account>[];
    _accountId ??= _seedAccountId(_flatten(accounts));

    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Row(
        children: [
          Icon(
            _message.channel == 'sms' ? Icons.sms_outlined : Icons.notifications_outlined,
            size: 20,
          ),
          const SizedBox(width: kSpaceLg),
          const Expanded(child: Text('Review captured expense')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildProvenance(theme),
              if (_message.error != null) ...[
                kGapXl,
                _buildWarning(theme, _message.error!),
              ],
              kGapXl,

              // ── amount + currency ──
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        CurrencyInputFormatter(currency: _currency),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        prefixText: CurrencyFormatter.prefixFor(_currency),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final parsed = CurrencyFormatter.parse(
                            value ?? '', currency: _currency);
                        if (parsed <= 0) return 'Enter an amount';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: kSpaceLg),
                  // Fixed width rather than a flex factor: a flex share of a
                  // phone-width dialog is narrower than the dropdown's own
                  // arrow plus label, which overflows.
                  SizedBox(
                    width: 104,
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Currency',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'COP', child: Text('COP')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _currency = value);
                      },
                    ),
                  ),
                ],
              ),
              kGapXl,

              // ── merchant / place name: the override the app will remember ──
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Name',
                  helperText: _merchantKey == null
                      ? 'No merchant found in the message'
                      : 'Bank sent: ${_message.merchantRaw}',
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Enter a name' : null,
              ),
              kGapXl,

              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'expense', child: Text('Expense')),
                  DropdownMenuItem(value: 'income', child: Text('Income')),
                  DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _type = value;
                    _categorySelection = null;
                    if (value != 'transfer') _targetAccountId = null;
                  });
                },
              ),
              kGapXl,

              accountsAsync.when(
                data: (data) => DropdownButtonFormField<String>(
                  value: _accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Account',
                    border: OutlineInputBorder(),
                  ),
                  items: _accountItems(_flatten(data)),
                  onChanged: (value) => setState(() => _accountId = value),
                  validator: (value) =>
                      value == null ? 'Select an account' : null,
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) =>
                    Text(friendlyError(e, action: 'load accounts')),
              ),

              if (_type == 'transfer') ...[
                kGapXl,
                accountsAsync.when(
                  data: (data) => DropdownButtonFormField<String>(
                    value: _targetAccountId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Destination account',
                      border: OutlineInputBorder(),
                    ),
                    items: _accountItems(_flatten(data), excludeId: _accountId),
                    onChanged: (value) =>
                        setState(() => _targetAccountId = value),
                    validator: (value) =>
                        value == null ? 'Select the destination' : null,
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) =>
                      Text(friendlyError(e, action: 'load accounts')),
                ),
              ],

              if (_type != 'transfer') ...[
                kGapXl,
                categoriesAsync.when(
                  data: (categories) => DropdownButtonFormField<String>(
                    value: _categorySelection,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: _categoryItems(categories),
                    onChanged: (value) =>
                        setState(() => _categorySelection = value),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) =>
                      Text(friendlyError(e, action: 'load categories')),
                ),
              ],

              kGapXl,
              expenseGroupsAsync.when(
                data: (groups) => DropdownButtonFormField<String?>(
                  value: _expenseGroupId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Expense group (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None', style: AppText.subtitle),
                    ),
                    ...groups.map((group) => DropdownMenuItem<String?>(
                          value: group.id,
                          child: Text(group.name,
                              style: AppText.subtitle,
                              overflow: TextOverflow.fade),
                        )),
                  ],
                  onChanged: (value) =>
                      setState(() => _expenseGroupId = value),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              kGapXl,
              _buildWhenAndWhere(theme),

              kGapXl,
              const Divider(),
              _buildMemorySection(theme, _flatten(accounts)),
            ],
          ),
        ),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      // Three buttons do not fit on one line at phone width.
      actionsOverflowButtonSpacing: kSpaceSm,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => _dismiss(),
          child: const Text('Dismiss'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  /// Where the message came from and how sure the parser was — shown up front
  /// so the user can judge the suggestion before trusting it.
  Widget _buildProvenance(ThemeData theme) {
    final sources = ref.watch(captureSourcesProvider).valueOrNull ?? const [];
    final source =
        sources.where((s) => s.id == _message.sourceId).firstOrNull;
    final sourceName = source?.effectiveName ?? _message.sourceKey;

    final issuer = issuerDisplayName(_message.issuerKey);
    final confidence = _message.confidence;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: kSpaceMd,
          runSpacing: kSpaceSm,
          children: [
            _chip(theme, Icons.apps, sourceName),
            if (issuer.isNotEmpty) _chip(theme, Icons.account_balance, issuer),
            if (_message.cardLast4 != null)
              _chip(theme, Icons.credit_card, '•${_message.cardLast4}'),
            if (confidence != null)
              _chip(theme, Icons.insights,
                  '${(confidence * 100).round()}% match'),
          ],
        ),
        kGapLg,
        InkWell(
          onTap: () => setState(() => _showRawMessage = !_showRawMessage),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: kSpaceSm),
            child: Row(
              children: [
                Icon(
                  _showRawMessage ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                const SizedBox(width: kSpaceSm),
                Text('Original message',
                    style: theme.textTheme.labelMedium),
              ],
            ),
          ),
        ),
        if (_showRawMessage)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(kSpaceLg),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              [
                if (_message.title != null && _message.title!.isNotEmpty)
                  _message.title!,
                _message.body,
              ].join('\n'),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _chip(ThemeData theme, IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: kSpaceLg, vertical: kSpaceSm),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: kSpaceSm),
            Text(label, style: AppText.badge),
          ],
        ),
      );

  Widget _buildWarning(ThemeData theme, String text) => Container(
        padding: const EdgeInsets.all(kSpaceXl),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: kSpaceLg),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      );

  /// The time and place of the payment, both captured at the moment the bank
  /// message arrived.
  Widget _buildWhenAndWhere(ThemeData theme) {
    final dateLabel = DateFormat('dd/MM/yyyy HH:mm', 'en').format(_occurredAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _pickDateTime,
          icon: const Icon(Icons.schedule, size: 18),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(dateLabel, style: AppText.subtitle),
          ),
        ),
        if (_message.hasLocation) ...[
          kGapLg,
          Row(
            children: [
              Icon(Icons.place_outlined,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: kSpaceLg),
              Expanded(
                child: Text(
                  _message.locationLabel ??
                      '${_message.latitude!.toStringAsFixed(5)}, '
                          '${_message.longitude!.toStringAsFixed(5)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// The learning controls. Each one writes a rule that removes a decision
  /// from every future message of the same shape.
  Widget _buildMemorySection(ThemeData theme, List<Account> accounts) {
    final key = _merchantKey;
    final name = _nameController.text.trim();
    final accountName = accounts
        .where((a) => a.id == _accountId)
        .map((a) => a.name)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: kSpaceLg, bottom: kSpaceSm),
          child: Text('Remember for next time',
              style: theme.textTheme.labelLarge),
        ),
        SwitchListTile(
          value: key != null && _rememberName,
          onChanged: key == null
              ? null
              : (value) => setState(() => _rememberName = value),
          title: const Text('Save this name and category',
              style: AppText.subtitle),
          subtitle: Text(
            key == null
                ? 'Needs a merchant in the message'
                : 'Messages for "$key" will be named "${name.isEmpty ? '…' : name}"',
            style: AppText.caption,
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        SwitchListTile(
          value: key != null && _rememberName && _autoPostNext,
          onChanged: (key == null || !_rememberName)
              ? null
              : (value) => setState(() => _autoPostNext = value),
          title: const Text('Record future ones automatically',
              style: AppText.subtitle),
          subtitle: const Text(
            'Skips this review when the next message matches',
            style: AppText.caption,
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (_message.cardLast4 != null)
          SwitchListTile(
            value: _accountId != null && _rememberCard,
            onChanged: _accountId == null
                ? null
                : (value) => setState(() => _rememberCard = value),
            title: Text('Link card •${_message.cardLast4} to this account',
                style: AppText.subtitle),
            subtitle: Text(
              accountName == null
                  ? 'Select an account first'
                  : 'Future messages for •${_message.cardLast4} use $accountName',
              style: AppText.caption,
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
      ],
    );
  }

  String? _seedAccountId(List<Account> accounts) {
    // The ingest pipeline already resolved an account when it could; it lives
    // on the alias that matched, so re-resolve through the same alias.
    final aliases = ref.read(merchantAliasesProvider).valueOrNull;
    if (aliases != null) {
      final alias = MerchantAlias.bestMatch(aliases, _merchantKey);
      final aliasAccount = alias?.accountId;
      if (aliasAccount != null &&
          accounts.any((a) => a.id == aliasAccount)) {
        return aliasAccount;
      }
    }
    final sources = ref.read(captureSourcesProvider).valueOrNull ?? const [];
    final defaultAccount = sources
        .where((s) => s.id == _message.sourceId)
        .firstOrNull
        ?.defaultAccountId;
    if (defaultAccount != null &&
        accounts.any((a) => a.id == defaultAccount)) {
      return defaultAccount;
    }
    return null;
  }

  List<DropdownMenuItem<String>> _accountItems(List<Account> accounts,
      {String? excludeId}) {
    return accounts
        .where((account) => account.id != excludeId)
        .map((account) => DropdownMenuItem(
              value: account.id,
              child: Text(
                account.isPocket ? '  ↳ ${account.name}' : account.name,
                style: AppText.subtitle,
                overflow: TextOverflow.fade,
              ),
            ))
        .toList();
  }

  /// Mirrors `AddTransactionDialog`: sub-categories are offered as
  /// "Parent > Child" entries carrying the sub-category id as the value.
  List<DropdownMenuItem<String>> _categoryItems(List<Category> categories) {
    final wanted = _type == 'income' ? 'income' : 'expense';
    final items = <DropdownMenuItem<String>>[];
    for (final category in categories) {
      if (category.type != wanted) continue;
      final subs = category.subCategories;
      if (subs != null && subs.isNotEmpty) {
        for (final sub in subs) {
          items.add(DropdownMenuItem(
            value: sub.id,
            child: Text('${category.name} > ${sub.name}',
                style: AppText.subtitle,
                overflow: TextOverflow.fade),
          ));
        }
      } else {
        items.add(DropdownMenuItem(
          value: category.id,
          child: Text(category.name,
              style: AppText.subtitle,
              overflow: TextOverflow.fade),
        ));
      }
    }
    return items;
  }

  /// Resolves the dropdown selection back into (category, sub-category).
  ({String? categoryId, String? subCategoryId}) _resolveCategory() {
    final selection = _categorySelection;
    if (selection == null) return (categoryId: null, subCategoryId: null);
    final categories = ref.read(categoriesProvider).valueOrNull ?? const [];
    for (final category in categories) {
      if (category.id == selection) {
        return (categoryId: category.id, subCategoryId: null);
      }
      final subs = category.subCategories;
      if (subs == null) continue;
      for (final sub in subs) {
        if (sub.id == selection) {
          return (categoryId: category.id, subCategoryId: sub.id);
        }
      }
    }
    return (categoryId: null, subCategoryId: null);
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(_occurredAt.year - 2),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (!mounted) return;
    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _occurredAt.hour,
        time?.minute ?? _occurredAt.minute,
      );
    });
  }

  Future<void> _dismiss() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(messageCaptureRepositoryProvider)
          .updateCapture(_message.id, {'status': 'dismissed'});
      ref.invalidate(pendingCapturesProvider);
      ref.invalidate(captureHistoryProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'dismiss message'))),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final repository = ref.read(messageCaptureRepositoryProvider);
    final name = _nameController.text.trim();
    final amount =
        CurrencyFormatter.parse(_amountController.text, currency: _currency);
    final category = _resolveCategory();
    final key = _merchantKey;

    try {
      // 1. Write the memory first, so the rule survives even if the posting
      //    fails and the user retries.
      if (key != null && key.isNotEmpty && _rememberName) {
        await repository.upsertAlias(
          pattern: key,
          displayName: name,
          categoryId: category.categoryId,
          subCategoryId: category.subCategoryId,
          expenseGroupId: _expenseGroupId,
          accountId: _accountId,
          movementType: _kindForType().movementType,
          autoPost: _autoPostNext,
        );
      }
      if (_message.cardLast4 != null && _accountId != null && _rememberCard) {
        await repository.upsertCardMapping(
          issuerKey: _message.issuerKey,
          last4: _message.cardLast4!,
          accountId: _accountId!,
        );
      }

      // 2. Post the transaction through the same path the automatic flow uses,
      //    so a confirmed expense is shaped identically to an auto-posted one.
      final parsed = ParsedMessage(
        status: ParseStatus.parsed,
        kind: _kindForType(),
        issuerKey: _message.issuerKey,
        amount: amount,
        currency: _currency,
        merchantRaw: _message.merchantRaw,
        merchantKey: key,
        cardLast4: _message.cardLast4,
        occurredAt: _occurredAt,
        confidence: _message.confidence ?? 1.0,
      );

      final accounts = ref.read(accountsProvider).valueOrNull ?? const [];
      final banks = ref.read(banksFutureProvider).valueOrNull ?? const [];

      final transactionId =
          await ref.read(captureIngestServiceProvider).postTransaction(
                message: _message,
                parsed: parsed,
                accountId: _accountId!,
                merchantDisplay: name,
                categoryId: category.categoryId,
                subCategoryId: category.subCategoryId,
                expenseGroupId: _expenseGroupId,
                movementType: _kindForType().movementType,
                targetAccountId: _targetAccountId,
                accountsById: {
                  for (final account in _flatten(accounts)) account.id: account
                },
                banksById: {for (final bank in banks) bank.id: bank},
              );

      await repository.updateCapture(_message.id, {
        'status': 'posted',
        'transaction_id': transactionId,
        'merchant_display': name,
        'amount': amount,
        'currency': _currency,
        'occurred_at': _occurredAt.toUtc().toIso8601String(),
        'error': null,
      });

      ref.invalidate(pendingCapturesProvider);
      ref.invalidate(captureHistoryProvider);
      ref.invalidate(merchantAliasesProvider);
      ref.invalidate(recentTransactionsProvider);
      ref.invalidate(accountsProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recorded $name')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'record expense'))),
      );
    }
  }

  /// The kind to record, with the Type dropdown as the authority.
  ///
  /// The parser's guess is only kept when it already agrees with the selected
  /// type — otherwise switching an income message to "Expense" would post an
  /// income row, because `transactionType` comes off the kind.
  MessageKind _kindForType() {
    final guess = _message.kind;
    if (guess != null && guess.transactionType == _type) return guess;
    return switch (_type) {
      'income' => MessageKind.transferIn,
      'transfer' => MessageKind.payment,
      _ => MessageKind.purchase,
    };
  }
}
