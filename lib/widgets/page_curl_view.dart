import 'dart:math' as math;
import 'package:flutter/material.dart';

enum TurnDirection { forward, backward, none }

/// Ultra-Fast Touch-Point Physical Page Curl Engine
/// Single full-page view with authentic book spine boundary & binding edge.
class RealisticPageCurl extends StatefulWidget {
  final int pageCount;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final IndexedWidgetBuilder builder;

  const RealisticPageCurl({
    super.key,
    required this.pageCount,
    required this.initialPage,
    required this.onPageChanged,
    required this.builder,
  });

  @override
  State<RealisticPageCurl> createState() => _RealisticPageCurlState();
}

class _RealisticPageCurlState extends State<RealisticPageCurl>
    with SingleTickerProviderStateMixin {
  late int _currentPage;
  late AnimationController _animController;
  Animation<double>? _progressAnim;

  final ValueNotifier<double> _curlProgressNotifier =
      ValueNotifier<double>(0.0);
  final Map<int, Widget> _pageWidgetCache = {};

  TurnDirection _turnDir = TurnDirection.none;
  Offset _touchStart = Offset.zero;
  double _dragProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  @override
  void didUpdateWidget(RealisticPageCurl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPage != widget.initialPage &&
        widget.initialPage != _currentPage) {
      _pageWidgetCache.clear();
      setState(() {
        _currentPage = widget.initialPage;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _curlProgressNotifier.dispose();
    super.dispose();
  }

  Widget _getCachedPage(int index) {
    if (!_pageWidgetCache.containsKey(index)) {
      final isCover = index == 0 || index == widget.pageCount - 1;
      _pageWidgetCache[index] = RepaintBoundary(
        child: _buildPaperWrapper(
          widget.builder(context, index),
          isCover: isCover,
        ),
      );
    }
    return _pageWidgetCache[index]!;
  }

  void _pruneCache() {
    final needed = {_currentPage - 1, _currentPage, _currentPage + 1};
    _pageWidgetCache.removeWhere((idx, _) => !needed.contains(idx));
  }

  void _onPanStart(DragStartDetails details) {
    if (_animController.isAnimating) return;
    final size = context.size ?? Size.zero;
    if (size.width == 0 || size.height == 0) return;

    final pos = details.localPosition;
    _touchStart = pos;

    // Forward: Right-to-Left (touch on right side)
    if (pos.dx >= size.width * 0.42) {
      if (_currentPage < widget.pageCount - 1) {
        _turnDir = TurnDirection.forward;
      } else {
        _turnDir = TurnDirection.none;
      }
    }
    // Backward: Left-to-Right (touch on left side)
    else if (pos.dx <= size.width * 0.58) {
      if (_currentPage > 0) {
        _turnDir = TurnDirection.backward;
      } else {
        _turnDir = TurnDirection.none;
      }
    } else {
      _turnDir = TurnDirection.none;
    }

    if (_turnDir != TurnDirection.none) {
      _dragProgress = 0.0;
      _curlProgressNotifier.value = 0.0;
      _getCachedPage(_currentPage);
      final target = _turnDir == TurnDirection.forward
          ? _currentPage + 1
          : _currentPage - 1;
      _getCachedPage(target);
      setState(() {});
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_turnDir == TurnDirection.none || _animController.isAnimating) return;
    final size = context.size ?? Size.zero;
    if (size.width == 0) return;

    final curX = details.localPosition.dx;
    double progress = 0.0;

    if (_turnDir == TurnDirection.forward) {
      final deltaX = _touchStart.dx - curX;
      progress = (deltaX / (size.width * 0.85)).clamp(0.0, 1.0);
    } else if (_turnDir == TurnDirection.backward) {
      final deltaX = curX - _touchStart.dx;
      progress = (deltaX / (size.width * 0.85)).clamp(0.0, 1.0);
    }

    _dragProgress = progress;
    _curlProgressNotifier.value = progress;
  }

  void _onPanEnd(DragEndDetails details) {
    if (_turnDir == TurnDirection.none || _animController.isAnimating) return;
    final vx = details.velocity.pixelsPerSecond.dx;

    bool shouldComplete = false;
    if (_turnDir == TurnDirection.forward) {
      if (_dragProgress > 0.28 || vx < -280) {
        shouldComplete = true;
      }
    } else if (_turnDir == TurnDirection.backward) {
      if (_dragProgress > 0.28 || vx > 280) {
        shouldComplete = true;
      }
    }

    final target = shouldComplete ? 1.0 : 0.0;
    final animMs = shouldComplete ? 180 : 130;
    _animController.duration = Duration(milliseconds: animMs);

    _progressAnim = Tween<double>(begin: _dragProgress, end: target).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _animController.reset();
    void listener() {
      if (_progressAnim != null) {
        _curlProgressNotifier.value = _progressAnim!.value;
      }
    }

    _animController.addListener(listener);

    _animController.forward().then((_) {
      _animController.removeListener(listener);
      if (shouldComplete) {
        final next = _turnDir == TurnDirection.forward
            ? _currentPage + 1
            : _currentPage - 1;
        setState(() {
          _currentPage = next;
          _dragProgress = 0.0;
          _turnDir = TurnDirection.none;
        });
        _pruneCache();
        widget.onPageChanged(next);
      } else {
        setState(() {
          _dragProgress = 0.0;
          _turnDir = TurnDirection.none;
        });
      }
    });
  }

  bool _isHardCover(int index, TurnDirection dir) {
    if (index == 0 && dir == TurnDirection.forward) return true;
    if (index == 1 && dir == TurnDirection.backward) return true;
    if (index == widget.pageCount - 2 && dir == TurnDirection.forward) {
      return true;
    }
    if (index == widget.pageCount - 1 && dir == TurnDirection.backward) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Single full page when not actively turning
              if (_turnDir == TurnDirection.none)
                _getCachedPage(_currentPage)
              else
                _buildActiveTurn(size),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveTurn(Size size) {
    final isCover = _isHardCover(_currentPage, _turnDir);
    final targetPage =
        _turnDir == TurnDirection.forward ? _currentPage + 1 : _currentPage - 1;

    final currWidget = _getCachedPage(_currentPage);
    final targetWidget = _getCachedPage(targetPage);

    if (isCover) {
      return ValueListenableBuilder<double>(
        valueListenable: _curlProgressNotifier,
        builder: (context, progress, _) {
          return _buildHardCoverAnimation(
              size, targetPage, progress, currWidget, targetWidget);
        },
      );
    } else {
      return ValueListenableBuilder<double>(
        valueListenable: _curlProgressNotifier,
        builder: (context, progress, _) {
          return _buildSoftPaperCurl(
              size, targetPage, progress, currWidget, targetWidget);
        },
      );
    }
  }

  // =========================================================================
  // 1. HARD COVER (Rigid Hinge at Book Spine, Board Bevel Depth)
  // =========================================================================
  Widget _buildHardCoverAnimation(
    Size size,
    int targetPage,
    double progress,
    Widget currWidget,
    Widget targetWidget,
  ) {
    final isForward = _turnDir == TurnDirection.forward;
    // Positive angle rotates Z towards viewer (pops outward in front of book)
    final angle = isForward ? progress * math.pi : (1.0 - progress) * math.pi;

    return Stack(
      fit: StackFit.expand,
      children: [
        targetWidget,
        if (progress > 0.05 && progress < 0.95)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: isForward
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    end: isForward
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    colors: [
                      Color.fromRGBO(
                          0, 0, 0, (math.sin(progress * math.pi) * 0.4)),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.4],
                  ),
                ),
              ),
            ),
          ),
        Transform(
          alignment: Alignment.centerLeft,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0009)
            ..rotateY(angle),
          child: currWidget,
        ),
      ],
    );
  }

  // =========================================================================
  // 2. SOFT PAPER CURL (Exposing Underlying Page ONLY in the Peeled Region)
  // =========================================================================
  Widget _buildSoftPaperCurl(
    Size size,
    int targetPage,
    double progress,
    Widget currWidget,
    Widget targetWidget,
  ) {
    final isForward = _turnDir == TurnDirection.forward;
    final touchY = _touchStart.dy;
    final touchYNorm =
        (size.height > 0) ? (touchY / size.height).clamp(0.05, 0.95) : 0.5;

    final tiltAngle = (touchYNorm - 0.5) * 0.45 * (1.0 - progress);

    final foldX =
        isForward ? size.width * (1.0 - progress) : size.width * progress;

    final curlRadius = math.sin(progress * math.pi) * 24.0 + 4.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Layer 1: Destination page revealed underneath the peel
        targetWidget,

        // Layer 2: Current unpeeled page surface
        ClipPath(
          clipper: _FastPaperClipper(
            foldX: foldX,
            tiltAngle: tiltAngle,
            touchY: touchY,
            isForward: isForward,
          ),
          child: currWidget,
        ),

        // Layer 3: Consolidated paper curl shading (Drop shadow, highlight & flap)
        RepaintBoundary(
          child: CustomPaint(
            painter: _UnifiedCurlShadingPainter(
              foldX: foldX,
              tiltAngle: tiltAngle,
              curlRadius: curlRadius,
              touchY: touchY,
              isForward: isForward,
              progress: progress,
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // 3. PHYSICAL BOOK PAPER WRAPPER WITH DISTINCT SPINE BOUNDARY
  // =========================================================================
  Widget _buildPaperWrapper(Widget child, {bool isCover = false}) {
    if (isCover) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2C1A10),
          border: Border.all(color: const Color(0xFFC49746), width: 1.5),
        ),
        child: child,
      );
    }

    return Container(
      color: const Color(0xFFF6F1E5), // Tasteful warm book paper
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,

          // --- BOOK SPINE BOUNDARY & INNER GUTTER SHADOW ---
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 24,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0x3D000000), // Deep spine gutter crease
                      Color(0x18000000), // Mid gutter transition
                      Colors.transparent, // Page face
                    ],
                    stops: [0.0, 0.40, 1.0],
                  ),
                  border: Border(
                    left: BorderSide(
                      color: Color(0x553E2723), // Book spine binding seam
                      width: 1.8,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // --- OUTER BOOK BLOCK TRIM (Right open-leaf edge) ---
          const Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x10000000),
                  border: Border(
                    right: BorderSide(
                      color: Color(0x20000000),
                      width: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FastPaperClipper extends CustomClipper<Path> {
  final double foldX;
  final double tiltAngle;
  final double touchY;
  final bool isForward;

  _FastPaperClipper({
    required this.foldX,
    required this.tiltAngle,
    required this.touchY,
    required this.isForward,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    final tanT = math.tan(tiltAngle);
    final topX = (foldX - tanT * touchY).clamp(0.0, size.width);
    final botX = (foldX + tanT * (size.height - touchY)).clamp(0.0, size.width);

    if (isForward) {
      path.moveTo(0, 0);
      path.lineTo(topX, 0);
      path.lineTo(botX, size.height);
      path.lineTo(0, size.height);
      path.close();
    } else {
      path.moveTo(topX, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(botX, size.height);
      path.close();
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _FastPaperClipper oldClipper) {
    return oldClipper.foldX != foldX ||
        oldClipper.tiltAngle != tiltAngle ||
        oldClipper.isForward != isForward;
  }
}

class _UnifiedCurlShadingPainter extends CustomPainter {
  final double foldX;
  final double tiltAngle;
  final double curlRadius;
  final double touchY;
  final bool isForward;
  final double progress;

  _UnifiedCurlShadingPainter({
    required this.foldX,
    required this.tiltAngle,
    required this.curlRadius,
    required this.touchY,
    required this.isForward,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.005) return;

    canvas.save();
    canvas.translate(foldX, size.height / 2);
    canvas.rotate(tiltAngle);
    canvas.translate(-foldX, -size.height / 2);

    // 1. Under-curl drop shadow on underlying page
    final shadowWidth = curlRadius * 2.2;
    final shadowRect = Rect.fromLTWH(
      isForward ? foldX : foldX - shadowWidth,
      0,
      shadowWidth,
      size.height,
    );
    final shadowOpacity = (math.sin(progress * math.pi) * 0.45).clamp(0.0, 1.0);
    if (shadowOpacity > 0.01) {
      final shadowPaint = Paint()
        ..shader = LinearGradient(
          begin: isForward ? Alignment.centerLeft : Alignment.centerRight,
          end: isForward ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            Color.fromRGBO(0, 0, 0, shadowOpacity),
            Colors.transparent,
          ],
        ).createShader(shadowRect);
      canvas.drawRect(shadowRect, shadowPaint);
    }

    // 2. Crease highlight on the curve
    final creaseWidth = curlRadius * 1.5;
    final creaseRect = Rect.fromLTWH(
      isForward ? foldX - creaseWidth : foldX,
      0,
      creaseWidth,
      size.height,
    );
    final creasePaint = Paint()
      ..shader = LinearGradient(
        begin: isForward ? Alignment.centerLeft : Alignment.centerRight,
        end: isForward ? Alignment.centerRight : Alignment.centerLeft,
        colors: const [
          Colors.transparent,
          Color(0x28000000),
          Color(0x75FFFDF7),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 0.85, 1.0],
      ).createShader(creaseRect);
    canvas.drawRect(creaseRect, creasePaint);

    // 3. Lifted reverse paper flap
    final flapWidth =
        math.min(size.width * progress * 0.75, math.pi * curlRadius * 2.2);
    if (flapWidth > 1.0) {
      final flapRect = Rect.fromLTWH(
        isForward ? foldX - flapWidth : foldX,
        0,
        flapWidth,
        size.height,
      );
      final flapPaint = Paint()
        ..shader = LinearGradient(
          begin: isForward ? Alignment.centerRight : Alignment.centerLeft,
          end: isForward ? Alignment.centerLeft : Alignment.centerRight,
          colors: const [
            Color(0xFFEDE4D2),
            Color(0xFFF7F2E7),
            Color(0xFFE8DDC6),
          ],
          stops: const [0.0, 0.75, 1.0],
        ).createShader(flapRect);
      canvas.drawRect(flapRect, flapPaint);

      final edgePaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      final edgeX = isForward ? flapRect.left : flapRect.right;
      canvas.drawLine(Offset(edgeX, 0), Offset(edgeX, size.height), edgePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UnifiedCurlShadingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.foldX != foldX ||
        oldDelegate.tiltAngle != tiltAngle;
  }
}
