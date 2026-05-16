// lib/widgets/sf_logo.dart
// Studyforge animated logo — book with a lightning bolt + pulsing glow ring.

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

class _SFLogoState extends State<SFLogo> with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulse = Tween(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;

    return SizedBox(
      width:  s + 20,
      height: s + 20,
      child: Stack(alignment: Alignment.center, children: [
        // ── Pulsing outer ring ────────────────────────────────────────────
        if (widget.animate)
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Transform.scale(
              scale: _pulse.value,
              child: Container(
                width:  s + 10,
                height: s + 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.22),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),

        // ── Static secondary ring ─────────────────────────────────────────
        Container(
          width:  s + 2,
          height: s + 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.primary.withOpacity(0.12),
              width: 1,
            ),
          ),
        ),

        // ── Logo circle with custom painter ──────────────────────────────
        Container(
          width:  s,
          height: s,
          decoration: const BoxDecoration(
            shape:    BoxShape.circle,
            gradient: AppColors.primaryGrad,
          ),
          child: CustomPaint(
            painter: _LogoPainter(s),
          ),
        ),
      ]),
    )
        .animate(target: widget.animate ? 1 : 0)
        .scale(duration: 700.ms, curve: Curves.elasticOut);
  }
}

// ── Custom painter ────────────────────────────────────────────────────────────
class _LogoPainter extends CustomPainter {
  final double size;
  _LogoPainter(this.size);

  @override
  void paint(Canvas canvas, Size sz) {
    final cx = sz.width  / 2;
    final cy = sz.height / 2;
    final k  = size / 80; // scale factor relative to design size 80

    final white     = Paint()..color = Colors.white;
    final white20   = Paint()..color = Colors.white.withOpacity(0.2);
    final white12   = Paint()..color = Colors.white.withOpacity(0.12);
    final purpleBolt = Paint()
      ..color = const Color(0xFF7C3AED).withOpacity(0.88);
    final linePaint = Paint()
      ..color       = const Color(0xFF7C3AED).withOpacity(0.38)
      ..strokeWidth = 2.5 * k
      ..strokeCap   = StrokeCap.round;

    final r = Radius.circular(3 * k);

    // Back shadow pages (layered depth effect)
    canvas.drawRRect(
      RRect.fromLTRBR(cx-18*k, cy-22*k, cx+4*k, cy+22*k, r),
      white12,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(cx-14*k, cy-26*k, cx+8*k, cy+20*k, r),
      white20,
    );

    // Main white book page
    canvas.drawRRect(
      RRect.fromLTRBR(cx-10*k, cy-28*k, cx+12*k, cy+22*k,
          Radius.circular(4.5 * k)),
      white,
    );

    // Horizontal ruled lines on the page
    canvas.drawLine(
      Offset(cx - 2*k, cy - 18*k), Offset(cx + 9*k, cy - 18*k), linePaint);
    canvas.drawLine(
      Offset(cx - 2*k, cy - 11*k), Offset(cx + 7*k, cy - 11*k), linePaint);
    canvas.drawLine(
      Offset(cx - 2*k, cy -  4*k), Offset(cx + 8*k, cy -  4*k), linePaint);

    // Lightning bolt overlaid on the page
    final bolt = Path()
      ..moveTo(cx + 9*k,  cy +  0*k)
      ..lineTo(cx + 1*k,  cy + 13*k)
      ..lineTo(cx + 6*k,  cy + 13*k)
      ..lineTo(cx - 3*k,  cy + 26*k)
      ..lineTo(cx + 11*k, cy +  9*k)
      ..lineTo(cx +  5*k, cy +  9*k)
      ..close();
    canvas.drawPath(bolt, purpleBolt);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
