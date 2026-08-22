import 'package:flutter/material.dart';

/// A balance figure that counts up/down smoothly to its new value,
/// instead of just snapping to it.
class AnimatedBalanceText extends StatelessWidget {
  final double value;
  final TextStyle? style;
  final String prefix;

  const AnimatedBalanceText({
    super.key,
    required this.value,
    this.style,
    this.prefix = 'Rs ',
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) {
        return Text('$prefix${val.toStringAsFixed(0)}', style: style);
      },
    );
  }
}