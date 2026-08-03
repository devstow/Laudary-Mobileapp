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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _btn(Icons.remove_rounded, value > min, () => onChanged(value - 1)),
        SizedBox(
          width: 38,
          child: Text('$value', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink)),
        ),
        _btn(Icons.add_rounded, value < max, () => onChanged(value + 1)),
      ]),
    );
  }

  Widget _btn(IconData icon, bool enabled, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 20, color: enabled ? AppColors.primary : AppColors.faint),
        ),
      ),
    );
  }
}
