import 'package:flutter/material.dart';

class DialogActionBar extends StatelessWidget {
  final VoidCallback? onDelete;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;
  final bool isLoading;
  final String saveLabel;
  final String deleteLabel;

  const DialogActionBar({
    super.key,
    this.onDelete,
    this.onSave,
    this.onCancel,
    this.isLoading = false,
    this.saveLabel = 'Save Changes',
    this.deleteLabel = 'Delete',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (onDelete != null)
          TextButton.icon(
            onPressed: isLoading ? null : onDelete,
            icon: const Icon(Icons.delete, color: Colors.red),
            label: Text(deleteLabel, style: const TextStyle(color: Colors.red)),
          )
        else
          const SizedBox.shrink(),
        Row(
          children: [
            TextButton(
              onPressed: onCancel ?? () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: isLoading ? null : onSave,
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(saveLabel),
            ),
          ],
        ),
      ],
    );
  }
}
