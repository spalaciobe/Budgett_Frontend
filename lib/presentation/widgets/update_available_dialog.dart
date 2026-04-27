import 'package:budgett_frontend/core/app_spacing.dart';
import 'package:budgett_frontend/core/services/update_checker_service.dart';
import 'package:budgett_frontend/presentation/providers/update_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ota_update/ota_update.dart';

class UpdateAvailableDialog extends ConsumerStatefulWidget {
  final UpdateInfo info;
  const UpdateAvailableDialog({super.key, required this.info});

  @override
  ConsumerState<UpdateAvailableDialog> createState() =>
      _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends ConsumerState<UpdateAvailableDialog> {
  double? _progress;
  String? _error;
  bool _downloading = false;

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    try {
      OtaUpdate()
          .execute(widget.info.apkUrl, destinationFilename: 'budgett-update.apk')
          .listen(
        (event) {
          if (!mounted) return;
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              final pct = double.tryParse(event.value ?? '');
              setState(() => _progress = pct == null ? null : pct / 100);
              break;
            case OtaStatus.INSTALLING:
              setState(() => _progress = 1);
              break;
            case OtaStatus.INSTALLATION_DONE:
              if (mounted) Navigator.of(context).pop();
              break;
            case OtaStatus.CANCELED:
              setState(() => _downloading = false);
              break;
            case OtaStatus.ALREADY_RUNNING_ERROR:
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            case OtaStatus.INTERNAL_ERROR:
            case OtaStatus.DOWNLOAD_ERROR:
            case OtaStatus.CHECKSUM_ERROR:
            case OtaStatus.INSTALLATION_ERROR:
              setState(() {
                _error = event.value ?? event.status.toString();
                _downloading = false;
              });
              break;
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _error = e.toString();
              _downloading = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _downloading = false;
        });
      }
    }
  }

  Future<void> _later() async {
    await dismissUpdate(widget.info.latestBuildNumber);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: kDialogPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.system_update, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Update available',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Version ${info.latestVersionName} (build ${info.latestBuildNumber}) '
              'is available. You have ${info.currentVersionName} '
              '(build ${info.currentBuildNumber}).',
              style: theme.textTheme.bodyMedium,
            ),
            if ((info.releaseNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text("What's new", style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes!.trim(),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ],
            if (_progress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 4),
              Text(
                _progress! >= 1
                    ? 'Opening installer…'
                    : 'Downloading ${(_progress! * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                'Error: $_error',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed: _downloading ? null : _later,
                    child: const Text('Later'),
                  ),
                  FilledButton.icon(
                    onPressed: _downloading ? null : _startDownload,
                    icon: const Icon(Icons.download),
                    label: Text(_error != null ? 'Retry' : 'Download'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
