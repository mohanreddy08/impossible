import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Large single-choice option (icon + words + check, so selection is not shown by colour alone).
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    checked: selected,
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(Tk.rButton),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Tk.minTouch),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Tk.mintSoft : Colors.white,
          borderRadius: BorderRadius.circular(Tk.rButton),
          border: Border.all(
            color: selected ? Tk.primary : Tk.border,
            width: selected ? 2 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? Tk.primary : Tk.textMuted,
            ),
            const SizedBox(width: 12),
            if (icon != null) ...[
              Icon(icon, size: 20, color: Tk.primaryDark),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
