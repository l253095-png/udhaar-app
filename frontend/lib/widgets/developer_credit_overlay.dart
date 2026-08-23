import 'package:flutter/material.dart';

/// A one-time animated overlay that shows the developer's photo
/// scaling/fading in, followed by a "Developed by Muaz" message,
/// then fades the whole thing out.
///
/// Usage (e.g. in owner_dashboard.dart):
///
///   bool _showCredit = true;
///
///   @override
///   Widget build(BuildContext context) {
///     return Stack(
///       children: [
///         Scaffold( ... your existing dashboard body ... ),
///         if (_showCredit)
///           DeveloperCreditOverlay(
///             onFinished: () => setState(() => _showCredit = false),
///           ),
///       ],
///     );
///   }
///
/// Don't forget to:
/// 1. Save your photo as: assets/images/developer_photo.png
/// 2. Add to pubspec.yaml:
///      flutter:
///        assets:
///          - assets/images/developer_photo.png
class DeveloperCreditOverlay extends StatefulWidget {
  final VoidCallback? onFinished;
  final String message;
  final String imagePath;

  const DeveloperCreditOverlay({
    super.key,
    this.onFinished,
    this.message = 'Developed by Muaz',
    this.imagePath = 'assets/images/developer_photo.png',
  });

  @override
  State<DeveloperCreditOverlay> createState() =>
      _DeveloperCreditOverlayState();
}

class _DeveloperCreditOverlayState extends State<DeveloperCreditOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _photoScale;
  late final Animation<double> _photoFade;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _textFade;
  late final Animation<double> _overlayFade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    // Photo: pops in with a slight overshoot (0% - 25% of timeline)
    _photoScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.4, end: 1.08)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 55,
      ),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 30),
    ]).animate(_controller);

    _photoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.25, curve: Curves.easeIn),
    );

    // Text: slides up + fades in (30% - 55% of timeline)
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.30, 0.55, curve: Curves.easeOutCubic),
      ),
    );

    _textFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.30, 0.55, curve: Curves.easeIn),
    );

    // Whole overlay fades out at the end (82% - 100%)
    _overlayFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.82, 1.0, curve: Curves.easeIn),
    );

    _controller.forward().whenComplete(() {
      widget.onFinished?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: 1 - _overlayFade.value,
            child: Container(
              color: const Color(0xCC1B3A4B), // Deep Indigo, semi-transparent
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: _photoFade.value,
                    child: Transform.scale(
                      scale: _photoScale.value,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFF4A322), // Marigold
                            width: 3,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                          image: DecorationImage(
                            image: AssetImage(widget.imagePath),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textFade,
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Color(0xFFFFF8ED), // Warm Cream
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
