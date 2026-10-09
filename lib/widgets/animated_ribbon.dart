import 'package:flutter/material.dart';

class AnimatedRibbonBookmark extends StatelessWidget {
  final bool isBookmarked;

  const AnimatedRibbonBookmark({super.key, required this.isBookmarked});

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      top: isBookmarked ? 0 : -88,
      right: 28,
      child: CustomPaint(
        size: const Size(26, 75),
        painter: _RibbonPainter(),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC62828)
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black38
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - 12)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path.shift(const Offset(2, 3)), shadowPaint);
    canvas.drawPath(path, paint);

    // Gold Stitch
    final goldPaint = Paint()
      ..color = const Color(0xFFFFD54F)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(3, 0), Offset(3, size.height - 12), goldPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
