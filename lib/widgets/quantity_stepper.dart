import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A compact −/+ quantity control.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 100000,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    // Claundry-style: two small bordered square buttons around the number.
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _btn(Icons.remove_rounded, value > min, () => onChanged(value - 1), filled: false),
      SizedBox(
        width: 34,
        child: Text('$value', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: AppColors.ink)),
      ),
      _btn(Icons.add_rounded, value < max, () => onChanged(value + 1), filled: true),
    ]);
  }

  Widget _btn(IconData icon, bool enabled, VoidCallback onTap, {required bool filled}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: Ink(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: filled && enabled ? AppColors.brandGradient : null,
            color: filled && enabled ? null : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: filled && enabled ? Colors.transparent : AppColors.line),
          ),
          child: Icon(icon, size: 18, color: filled && enabled ? Colors.white : (enabled ? AppColors.ink : AppColors.faint)),
        ),
      ),
    );
  }
}
