import 'package:flutter/material.dart';

class ColorPickerRow extends StatelessWidget {
  final List<String> colorOptions;
  final String selectedColor;
  final ValueChanged<String> onColorSelected;

  const ColorPickerRow({
    super.key,
    required this.colorOptions,
    required this.selectedColor,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: colorOptions.map((colorStr) {
          final color = Color(int.parse(colorStr));
          final isSelected = selectedColor == colorStr;

          return GestureDetector(
            onTap: () => onColorSelected(colorStr),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
              ),
              child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}
