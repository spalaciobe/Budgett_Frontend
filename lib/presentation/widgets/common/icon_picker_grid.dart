import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/icon_helper.dart';

class IconPickerGrid extends StatelessWidget {
  final List<String> iconOptions;
  final String selectedIcon;
  final ValueChanged<String> onIconSelected;

  const IconPickerGrid({
    super.key,
    required this.iconOptions,
    required this.selectedIcon,
    required this.onIconSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: iconOptions.map((iconKey) {
        final isSelected = iconKey == selectedIcon;
        return InkWell(
          onTap: () => onIconSelected(iconKey),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              IconHelper.getIcon(iconKey),
              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
              size: 24,
            ),
          ),
        );
      }).toList(),
    );
  }
}
