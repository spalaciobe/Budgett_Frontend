import 'package:flutter/material.dart';
import 'package:budgett_frontend/presentation/utils/currency_formatter.dart';

class CurrencyFormField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? helperText;
  final bool allowNegative;
  final bool required;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  const CurrencyFormField({
    super.key,
    required this.controller,
    required this.labelText,
    this.helperText,
    this.allowNegative = false,
    this.required = true,
    this.onChanged,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: labelText,
        prefixText: '\$',
        border: const OutlineInputBorder(),
        helperText: helperText,
      ),
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: allowNegative,
      ),
      inputFormatters: [CurrencyInputFormatter()],
      autofocus: autofocus,
      onChanged: onChanged,
      validator: (value) {
        if (!required && (value == null || value.isEmpty)) return null;
        if (value == null || value.isEmpty) return 'Required';
        if (CurrencyFormatter.parse(value) == 0.0 && value != '0' && value != '0.0') {
          return 'Invalid number';
        }
        return null;
      },
    );
  }
}
