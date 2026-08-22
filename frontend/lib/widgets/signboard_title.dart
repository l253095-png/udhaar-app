import 'package:flutter/material.dart';

/// AppBar title that swings gently into place on load, like a hanging
/// market signboard settling after being put up.
class SignboardTitle extends StatefulWidget {
  final String text;
  const SignboardTitle({super.key, required this.text});

  @override
  State<SignboardTitle> createState() => _SignboardTitleState();
}

class _SignboardTitleState extends State<SignboardTitle> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _swing;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _swing = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: -0.08, end: 0.05).chain(CurveTween(curve: Curves.easeOut)), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.05, end: -0.03).chain(CurveTween(curve: Curves.easeInOut)), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.03, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 1),
    ]).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _swing,
      builder: (context, child) {
        return Transform.rotate(
          angle: _swing.value,
          alignment: Alignment.topCenter,
          child: child,
        );
      },
      child: Text(widget.text),
    );
  }
}