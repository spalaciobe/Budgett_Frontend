import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CurrencyFormatter {
  /// Formats a double value as currency with thousands separators.
  static String format(double amount, {int decimalDigits = 0, bool includeSymbol = true}) {
    final formatter = NumberFormat.currency(
      locale: 'en_US', 
      symbol: includeSymbol ? '\$' : '', 
      decimalDigits: decimalDigits
    );
    return formatter.format(amount).trim();
  }

  static double parse(String value) {
    return double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Determine if we are handling decimals
    // Standard approach: treat input as typing numbers and formatting them
    
    // Remove all non-digits (and keep only one decimal point if exists)
    String newText = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    
    // Check if user is trying to add a second decimal point
    if (newText.indexOf('.') != newText.lastIndexOf('.')) {
      return oldValue;
    }

    // Split integer and decimal parts
    List<String> parts = newText.split('.');
    String integerPart = parts[0];
    String? decimalPart = parts.length > 1 ? parts[1] : null;

    // Format integer part
    if (integerPart.isNotEmpty) {
      final formatter = NumberFormat('#,###', 'en_US');
      integerPart = formatter.format(int.parse(integerPart));
    }
    
    // Reassemble
    String formattedText = integerPart;
    if (newText.contains('.') || decimalPart != null) {
      formattedText += '.';
      if (decimalPart != null) {
        // Limit decimals to 2
        if (decimalPart.length > 2) {
            decimalPart = decimalPart.substring(0, 2);
        }
        formattedText += decimalPart;
      }
    }

    // Calculate selection index
    // This is tricky with separators. Simple heuristic: keep cursor at end if adding, or try to respect position.
    // Given the complexity of maintaining cursor in middle with separators adding/removing, 
    // forcing cursor to end is a common simplification for financial apps unless using a very robust library.
    // However, let's try to be slightly smarter or just return end for now to ensure stability.
    
    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}
