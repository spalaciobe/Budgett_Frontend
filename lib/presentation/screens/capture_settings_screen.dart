import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/core/parsing/issuer_registry.dart';
import 'package:budgett_frontend/core/services/capture_ingest_service.dart';
import 'package:budgett_frontend/core/services/message_capture_service.dart';
import 'package:budgett_frontend/core/utils/error_messages.dart';
import 'package:budgett_frontend/data/models/account_model.dart';
import 'package:budgett_frontend/data/models/capture_source_model.dart';
import 'package:budgett_frontend/data/models/category_model.dart';
import 'package:budgett_frontend/data/models/merchant_alias_model.dart';
import 'package:budgett_frontend/presentation/providers/finance_provider.dart';
import 'package:budgett_frontend/presentation/providers/message_capture_provider.dart';
import 'package:budgett_frontend/presentation/providers/settings_provider.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';
import '../../core/app_text.dart';
import '../widgets/screen_title.dart';

/// Controls for the capture pipeline: what it listens to, how bold it is
/// allowed to be, and what it has learned so far.
class CaptureSettingsScreen extends ConsumerWidget {
  const CaptureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(captureStatusProvider);
    final settingsAsync = ref.watch(captureSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: ScreenTitle('Expense capture')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: kScreenPadding,
            children: [
              statusAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Card(
                  child: Padding(
                    padding: kCardPadding,
                    child: Text(
                        friendlyError(error, action: 'read capture status')),
                  ),
                ),
                data: (status) => _SourcesAndPermissions(status: status),
              ),
              kGapXl,
              settingsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (settings) => _AutomationCard(settings: settings),
              ),
              kGapXl,
              const _KnownSourcesCard(),
              kGapXl,
              const _RememberedMerchantsCard(),
              kGapXxl,
            ],
          ),
        ),
      ),
    );
  }
}

class _SourcesAndPermissions extends ConsumerWidget {
  final CaptureStatus status;

  const _SourcesAndPermissions({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(messageCaptureServiceProvider);

    if (!status.isSupported) {
      return Card(
        child: Padding(
          padding: kCardPadding,
          child: Row(
            children: [
              const Icon(Icons.phone_android),
              const SizedBox(width: kSpaceXl),
              const Expanded(
                child: Text(
                  'Reading notifications and SMS is only possible on Android. '
                  'Capture what you spend on your phone and it syncs here.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    Future<void> refresh() async {
      ref.invalidate(captureStatusProvider);
      await ref.read(captureStatusProvider.future);
    }

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            value: status.enabled,
            title: const Text('Capture expenses from messages'),
            subtitle: const Text(
                'Reads bank notifications and SMS to record what you spend'),
            onChanged: (value) async {
              await service.applyConfig(enabled: value);
              await refresh();
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              status.notificationAccess ? Icons.check_circle : Icons.circle_outlined,
              color: status.notificationAccess
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
            title: const Text('Notification access'),
            subtitle: Text(status.notificationAccess
                ? 'Granted'
                : 'Needed to read bank notifications'),
            trailing: status.notificationAccess
                ? null
                : TextButton(
                    onPressed: () async {
                      await service.openNotificationAccessSettings();
                      // Android gives no callback for this grant, so the
                      // status is re-read when the user comes back.
                      await refresh();
                    },
                    child: const Text('Grant'),
                  ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: status.smsEnabled,
            title: const Text('Include SMS'),
            subtitle: Text(status.smsEnabled && !status.smsPermission
                ? 'Permission not granted yet'
                : 'Many banks send an SMS as well as a notification'),
            onChanged: (value) async {
              await service.applyConfig(smsEnabled: value);
              if (value && !status.smsPermission) {
                await service.requestSmsPermission();
              }
              await refresh();
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: status.locationEnabled,
            title: const Text('Record where you paid'),
            subtitle: Text(
              status.locationEnabled && !status.backgroundLocationPermission
                  ? 'Needs location set to "Allow all the time"'
                  : 'Takes a GPS fix the moment the message arrives',
            ),
            onChanged: (value) async {
              await service.applyConfig(locationEnabled: value);
              if (value && !status.backgroundLocationPermission) {
                final granted = await service.requestBackgroundLocation();
                // On Android 11+ "Allow all the time" can only be chosen in
                // app settings, so point the user there instead of silently
                // leaving location off.
                if (!granted && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                          'Set location to "Allow all the time" to record '
                          'where you paid'),
                      action: SnackBarAction(
                        label: 'Open settings',
                        onPressed: service.openSystemAppSettings,
                      ),
                    ),
                  );
                }
              }
              await refresh();
            },
          ),
          if (status.queued > 0) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: Text('${status.queued} message(s) waiting on this device'),
              subtitle: const Text('Processed the next time the inbox syncs'),
              trailing: TextButton(
                onPressed: () async {
                  final result = await ref
                      .read(captureIngestControllerProvider.notifier)
                      .run();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(result?.summary ?? 'Nothing to process')),
                  );
                  await refresh();
                },
                child: const Text('Process'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AutomationCard extends ConsumerWidget {
  final CaptureSettings settings;

  const _AutomationCard({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(captureSettingsProvider.notifier);
    final cap = settings.autoPostMaxAmount;

    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Automation',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          SwitchListTile(
            value: settings.autoPostEnabled,
            title: const Text('Record known expenses automatically'),
            subtitle: const Text(
                'Only for merchants you have already confirmed once'),
            onChanged: notifier.setAutoPost,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.price_check),
            title: const Text('Always review above'),
            subtitle: Text(cap <= 0
                ? 'No limit — any amount can be recorded automatically'
                : CurrencyFormatter.format(cap)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editAmountCap(context, ref, cap),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.content_copy_outlined),
            title: const Text('Duplicate window'),
            subtitle: Text('${settings.dedupWindow.inMinutes} minutes between '
                'copies of the same payment'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                _editWindow(context, ref, settings.dedupWindow.inMinutes),
          ),
        ],
      ),
    );
  }

  Future<void> _editAmountCap(
      BuildContext context, WidgetRef ref, double current) async {
    final controller = TextEditingController(
      text: current <= 0
          ? ''
          : CurrencyFormatter.format(current,
              includeSymbol: false),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Always review above'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Expenses larger than this always wait for your confirmation. '
              'Leave empty for no limit.',
              style: AppText.subtitle,
            ),
            kGapXl,
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: const [CurrencyInputFormatter()],
              decoration: const InputDecoration(
                prefixText: '\$',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(CurrencyFormatter.parse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await ref.read(captureSettingsProvider.notifier)
          .setAutoPostMaxAmount(result);
    }
  }

  Future<void> _editWindow(
      BuildContext context, WidgetRef ref, int current) async {
    const options = [2, 5, 10, 20, 30, 60];
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Duplicate window'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Two messages with the same amount inside this window are '
              'treated as one payment.',
              style: AppText.subtitle,
            ),
            kGapXl,
            ...options.map((minutes) => ListTile(
                  leading: Icon(minutes == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
                  title: Text('$minutes minutes'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onTap: () => Navigator.of(dialogContext).pop(minutes),
                )),
          ],
        ),
      ),
    );

    if (result != null) {
      await ref
          .read(captureSettingsProvider.notifier)
          .setDedupWindowMinutes(result);
    }
  }
}

/// Every app and SMS sender that has ever sent us a message, with the rename
/// the user applied to it.
class _KnownSourcesCard extends ConsumerWidget {
  const _KnownSourcesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(captureSourcesProvider);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Message sources',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          sourcesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: kCardPadding,
              child: Text(friendlyError(error, action: 'load capture sources')),
            ),
            data: (sources) {
              if (sources.isEmpty) {
                return const Padding(
                  padding: kCardPadding,
                  child: Text(
                    'Nothing yet. Sources appear here after the first bank '
                    'message arrives — then you can rename them and pick a '
                    'default account.',
                    style: AppText.subtitle,
                  ),
                );
              }
              return Column(
                children: [
                  for (final source in sources)
                    _SourceTile(source: source),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends ConsumerWidget {
  final CaptureSource source;

  const _SourceTile({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final flattened = <Account>[
      for (final account in accounts) ...[account, ...account.pockets]
    ];
    final defaultAccount = flattened
        .where((a) => a.id == source.defaultAccountId)
        .firstOrNull;

    final details = <String>[
      if (source.hasOverride) source.detectedName ?? source.sourceKey,
      if (source.issuerKey != null) issuerDisplayName(source.issuerKey),
      if (defaultAccount != null) '→ ${defaultAccount.name}',
      '${source.messageCount} message(s)',
    ];

    return ListTile(
      leading: Icon(
        source.isSms ? Icons.sms_outlined : Icons.notifications_outlined,
        color: source.isEnabled
            ? null
            : Theme.of(context).colorScheme.outline,
      ),
      title: Text(source.effectiveName),
      subtitle: Text(details.join(' · '),
          maxLines: 2, overflow: TextOverflow.fade),
      trailing: Switch(
        value: source.isEnabled,
        onChanged: (value) => _toggle(context, ref, value),
      ),
      onTap: () => showDialog(
        context: context,
        builder: (_) => _EditSourceDialog(source: source),
      ),
    );
  }

  Future<void> _toggle(
      BuildContext context, WidgetRef ref, bool enabled) async {
    try {
      await ref
          .read(messageCaptureRepositoryProvider)
          .updateSource(source.id, {'is_enabled': enabled});
      ref.invalidate(captureSourcesProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'update source'))),
      );
    }
  }
}

/// Renames a source and pins its issuer / default account.
///
/// The rename is the point: banks identify themselves by package name
/// (`com.bancolombia…`) or by a numeric short code, neither of which is
/// readable. The override is stored and used everywhere afterwards.
class _EditSourceDialog extends ConsumerStatefulWidget {
  final CaptureSource source;

  const _EditSourceDialog({required this.source});

  @override
  ConsumerState<_EditSourceDialog> createState() => _EditSourceDialogState();
}

class _EditSourceDialogState extends ConsumerState<_EditSourceDialog> {
  late final TextEditingController _nameController;
  String? _issuerKey;
  String? _defaultAccountId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.source.displayName ?? '');
    _issuerKey = widget.source.issuerKey;
    _defaultAccountId = widget.source.defaultAccountId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final flattened = <Account>[
      for (final account in accounts) ...[account, ...account.pockets]
    ];

    return AlertDialog(
      scrollable: true,
      title: const Text('Edit source'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.source.sourceKey,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            kGapXl,
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: widget.source.detectedName ?? widget.source.sourceKey,
                helperText: 'Shown instead of the raw sender',
                border: const OutlineInputBorder(),
              ),
            ),
            kGapXl,
            DropdownButtonFormField<String?>(
              value: _issuerKey,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Bank',
                helperText: 'Improves parsing and duplicate detection',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('Detect automatically')),
                ...kIssuers.map((issuer) => DropdownMenuItem<String?>(
                      value: issuer.key,
                      child: Text(issuer.displayName),
                    )),
              ],
              onChanged: (value) => setState(() => _issuerKey = value),
            ),
            kGapXl,
            DropdownButtonFormField<String?>(
              value: _defaultAccountId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Default account',
                helperText: 'Used when the message has no card number',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('None')),
                ...flattened.map((account) => DropdownMenuItem<String?>(
                      value: account.id,
                      child: Text(account.name, overflow: TextOverflow.fade),
                    )),
              ],
              onChanged: (value) => setState(() => _defaultAccountId = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final name = _nameController.text.trim();
    try {
      await ref.read(messageCaptureRepositoryProvider).updateSource(
        widget.source.id,
        {
          'display_name': name.isEmpty ? null : name,
          'issuer_key': _issuerKey,
          'default_account_id': _defaultAccountId,
        },
      );
      ref.invalidate(captureSourcesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'save source'))),
      );
    }
  }
}

/// What the pipeline has learned: merchant → name, category and whether it may
/// record on its own.
class _RememberedMerchantsCard extends ConsumerWidget {
  const _RememberedMerchantsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aliasesAsync = ref.watch(merchantAliasesProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Remembered merchants',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          aliasesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: kCardPadding,
              child:
                  Text(friendlyError(error, action: 'load remembered merchants')),
            ),
            data: (aliases) {
              if (aliases.isEmpty) {
                return const Padding(
                  padding: kCardPadding,
                  child: Text(
                    'Nothing remembered yet. Confirm a captured expense once '
                    'and the merchant is saved here with its name and '
                    'category.',
                    style: AppText.subtitle,
                  ),
                );
              }
              return Column(
                children: [
                  for (final alias in aliases)
                    _AliasTile(alias: alias, categories: categories),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AliasTile extends ConsumerWidget {
  final MerchantAlias alias;
  final List<Category> categories;

  const _AliasTile({required this.alias, required this.categories});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryName =
        categories.where((c) => c.id == alias.categoryId).firstOrNull?.name;

    final details = <String>[
      alias.pattern,
      if (categoryName != null) categoryName,
      if (alias.hitCount > 0) 'used ${alias.hitCount}×',
    ];

    return ListTile(
      leading: Icon(
        alias.autoPost ? Icons.bolt : Icons.bookmark_border,
        color: alias.autoPost ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(alias.displayName),
      subtitle: Text(details.join(' · '),
          maxLines: 2, overflow: TextOverflow.fade),
      trailing: IconButton(
        tooltip: 'Forget',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _confirmDelete(context, ref),
      ),
      // Tapping used to flip auto-post with nothing on screen to say so, and
      // the name the pipeline had learned could not be corrected at all: the
      // only way out of a bad name was to forget the merchant and teach it
      // again from the next message.
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => EditMerchantSheet(alias: alias),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Forget ${alias.displayName}?'),
        content: const Text(
            'Future messages from this merchant will be reviewed again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref.read(messageCaptureRepositoryProvider).deleteAlias(alias.id);
      ref.invalidate(merchantAliasesProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'forget merchant'))),
      );
    }
  }
}


/// Renaming a remembered merchant, and deciding what happens to the movements
/// already recorded under the old name.
///
/// The rule matches on [MerchantAlias.pattern] -- the bank's own text, which
/// is never shown as a name -- so the name is free to be anything. What it is
/// not free of is history: the name is copied onto each transaction as it is
/// recorded, so a rename here leaves every past movement spelled the old way
/// unless we rewrite those too. That is what the checkbox is for.
class EditMerchantSheet extends ConsumerStatefulWidget {
  final MerchantAlias alias;

  const EditMerchantSheet({super.key, required this.alias});

  @override
  ConsumerState<EditMerchantSheet> createState() => _EditMerchantSheetState();
}

class _EditMerchantSheetState extends ConsumerState<EditMerchantSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.alias.displayName);
  late bool _autoPost = widget.alias.autoPost;
  bool _renamePast = true;
  bool _saving = false;

  /// How many movements carry the old name. Null while we are still counting;
  /// the checkbox only appears once we can say the number, because "also
  /// rename past movements" without one is a question the user cannot answer.
  int? _recorded;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _countRecorded();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _countRecorded() async {
    try {
      final count = await ref
          .read(messageCaptureRepositoryProvider)
          .countRecordedUnder(widget.alias.displayName);
      if (mounted) setState(() => _recorded = count);
    } catch (_) {
      // Counting is a courtesy; a rename must still be possible without it.
      if (mounted) setState(() => _recorded = 0);
    }
  }

  String get _trimmed => _name.text.trim();
  bool get _renamed => _trimmed != widget.alias.displayName;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final recorded = _recorded;
    final canSave = _trimmed.isNotEmpty && !_saving;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit merchant',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Messages are matched on "${widget.alias.pattern}", so renaming '
              'this only changes what you read.',
              style: AppText.caption.copyWith(color: muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _autoPost,
              onChanged: (v) => setState(() => _autoPost = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Record without asking'),
              subtitle: Text(
                _autoPost
                    ? 'Purchases here are filed straight away.'
                    : 'Purchases here wait in the inbox for review.',
                style: AppText.caption.copyWith(color: muted),
              ),
            ),
            if (_renamed && recorded != null && recorded > 0)
              CheckboxListTile(
                value: _renamePast,
                onChanged: (v) => setState(() => _renamePast = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Also rename the $recorded movement'
                  '${recorded == 1 ? '' : 's'} already recorded',
                  style: AppText.subtitle,
                ),
                subtitle: Text(
                  'Otherwise the same merchant shows up under both names in '
                  'your history.',
                  style: AppText.caption.copyWith(color: muted),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: canSave ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(messageCaptureRepositoryProvider);
    final oldName = widget.alias.displayName;
    final newName = _trimmed;

    try {
      await repo.updateAlias(widget.alias.id, {
        'display_name': newName,
        'auto_post': _autoPost,
      });

      var renamed = 0;
      if (_renamed && _renamePast) {
        renamed = await repo.renameRecordedMerchant(from: oldName, to: newName);
        // The movements themselves changed, so every list built on them is
        // now stale.
        ref.invalidate(recentTransactionsProvider);
      }
      ref.invalidate(merchantAliasesProvider);
      ref.invalidate(captureHistoryProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(renamed > 0
              ? 'Renamed to $newName, including $renamed past movement'
                  '${renamed == 1 ? '' : 's'}'
              : 'Saved'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'save merchant'))),
      );
    }
  }
}
