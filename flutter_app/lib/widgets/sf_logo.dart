// lib/widgets/sf_logo.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';

class SFLogo extends StatefulWidget {
  final double size;
  final bool animate;

  const SFLogo({super.key, this.size = 80, this.animate = true});

  @override
  State<SFLogo> createState() => _SFLogoState();
}

class _SFLogoState extends State<SFLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.animate) {
      // Start shimmer after the scale-in finishes (~700ms)
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) _shimmerCtrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;

    Widget logo = ClipRRect(
      borderRadius: BorderRadius.circular(s * 0.22),
      child: Image.asset(
        'assets/images/studyforge_logo.png',
        width: s,
        height: s,
        fit: BoxFit.cover,
      ),
    );

    // Shimmer sweep overlay
    Widget withShimmer = AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (_, __) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            // sweep from left (-1) to right (2) over animation progress
            final dx = -1.0 + _shimmerCtrl.value * 3.0;
            return LinearGradient(
              begin: Alignment(dx - 0.6, 0),
              end: Alignment(dx + 0.6, 0),
              colors: const [
                Colors.transparent,
                Color(0x55FFFFFF),
                Colors.transparent,
              ],
            ).createShader(bounds);
          },
          child: logo,
        );
      },
    );

    // Outer glow ring
    Widget withGlow = Stack(
      alignment: Alignment.center,
      children: [
        // Soft glow behind logo
        Container(
          width: s + 16,
          height: s + 16,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular((s + 16) * 0.26),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.25),
                blurRadius: 28,
                spreadRadius: 4,
              ),
            ],
          ),
        ),
        withShimmer,
      ],
    );

    if (!widget.animate) return withGlow;

    return withGlow
        .animate()
        .scale(
      begin: const Offset(0.0, 0.0),
      end: const Offset(1.0, 1.0),
      duration: 700.ms,
      curve: Curves.elasticOut,
    )
        .fadeIn(duration: 400.ms);
  }
}