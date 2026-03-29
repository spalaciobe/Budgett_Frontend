import 'package:flutter/material.dart';
import '../../data/models/bank_model.dart';

/// Visual card for a bank displayed during onboarding.
class BankCard extends StatelessWidget {
  final Bank bank;
  final bool isSelected;
  final VoidCallback onTap;

  const BankCard({
    super.key,
    required this.bank,
    required this.isSelected,
    required this.onTap,
  });

  /// Returns a color associated with each bank for visual identity.
  Color _bankColor(BuildContext context) {
    switch (bank.code) {
      case 'BANCOLOMBIA':
        return const Color(0xFFFDDA24); // Bancolombia yellow
      case 'NUBANK':
        return const Color(0xFF820AD1); // Nubank purple
      case 'DAVIVIENDA':
        return const Color(0xFFE4032E); // Davivienda red
      case 'BBVA':
        return const Color(0xFF004481); // BBVA blue
      case 'RAPPICARD':
        return const Color(0xFFFF441A); // Rappi orange-red
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  /// Returns an icon for each bank.
  IconData _bankIcon() {
    switch (bank.code) {
      case 'RAPPICARD':
        return Icons.delivery_dining;
      case 'NUBANK':
        return Icons.credit_card;
      default:
        return Icons.account_balance;
    }
  }

  /// Returns a short description of the bank's cut/payment rules.
  String _rulesDescription() {
    switch (bank.code) {
      case 'BANCOLOMBIA':
        return 'Corte fijo • Pago: día siguiente hábil';
      case 'NUBANK':
        return 'Corte fijo • Pago: día hábil anterior';
      case 'DAVIVIENDA':
        return 'Corte fijo • Pago: día siguiente hábil';
      case 'BBVA':
        return 'Corte fijo • Pago: día siguiente hábil';
      case 'RAPPICARD':
        return 'Corte: penúltimo día hábil • Pago: 10 días después';
      default:
        return 'Reglas automáticas';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _bankColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected
            ? color.withOpacity(isDark ? 0.25 : 0.12)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? color : Colors.transparent,
          width: 2.5,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: color.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 4))]
            : [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(
            children: [
              // Bank icon circle
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(_bankIcon(), color: color, size: 24),
              ),
              const SizedBox(width: 16),
              // Bank info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bank.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSelected ? color : null,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _rulesDescription(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                    ),
                  ],
                ),
              ),
              // Checkmark
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isSelected
                    ? Icon(Icons.check_circle_rounded, color: color, key: const ValueKey('checked'))
                    : Icon(Icons.radio_button_unchecked, color: Colors.grey.shade400, key: const ValueKey('unchecked')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
