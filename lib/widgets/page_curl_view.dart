import 'dart:math' as math;
import 'package:flutter/material.dart';

class RealisticPageCurl extends StatefulWidget {
  final int pageCount;
  final int initialPage;
  final Widget Function(BuildContext context, int pageIndex) builder;
  final ValueChanged<int> onPageChanged;
  final Color paperColor;
  final bool enablePaperTransparency;

  const RealisticPageCurl({
    super.key,
    required this.pageCount,
    required this.initialPage,
    required this.builder,
    required this.onPageChanged,
    this.paperColor = const Color(0xFFF5EACB),
    this.enablePaperTransparency = true,
  });

  @override
  State<RealisticPageCurl> createState() => _RealisticPageCurlState();
}

// Backward-compatibility alias
typedef PageCurlView = RealisticPageCurl;

class _RealisticPageCurlState extends State<RealisticPageCurl>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late int _currentPage;
  double _dragProgress = 0.0;
  bool _isForward = true;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )
      ..addListener(() {
        setState(() {
          _dragProgress = _animController.value;
        });
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          final nextIndex = _isForward ? _currentPage + 1 : _currentPage - 1;
          _isDragging = false;
          _dragProgress = 0.0;
          _animController.reset();
          if (nextIndex >= 0 && nextIndex < widget.pageCount) {
            setState(() {
              _currentPage = nextIndex;
            });
            widget.onPageChanged(nextIndex);
          }
        } else if (status == AnimationStatus.dismissed) {
          _isDragging = false;
          _dragProgress = 0.0;
        }
      });
  }

  @override
  void didUpdateWidget(RealisticPageCurl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPage != _currentPage &&
        !_isDragging &&
        !_animController.isAnimating) {
      setState(() {
        _currentPage = widget.initialPage;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_animController.isAnimating) return;
    final width = MediaQuery.of(context).size.width;
    final touchX = details.localPosition.dx;

    if (touchX > width * 0.5) {
      if (_currentPage < widget.pageCount - 1) {
        _isForward = true;
        _isDragging = true;
        _dragProgress = 0.0;
      }
    } else {
      if (_currentPage > 0) {
        _isForward = false;
        _isDragging = true;
        _dragProgress = 0.0;
      }
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    final width = MediaQuery.of(context).size.width;
    final delta = details.primaryDelta ?? 0.0;

    setState(() {
      if (_isForward) {
        _dragProgress = (_dragProgress - (delta / width)).clamp(0.0, 1.0);
      } else {
        _dragProgress = (_dragProgress + (delta / width)).clamp(0.0, 1.0);
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    final velocity = details.primaryVelocity ?? 0.0;

    if (_isForward) {
      if (_dragProgress > 0.3 || velocity < -400) {
        _animController.forward(from: _dragProgress);
      } else {
        _animController.reverse(from: _dragProgress);
      }
    } else {
      if (_dragProgress > 0.3 || velocity > 400) {
        _animController.forward(from: _dragProgress);
      } else {
        _animController.reverse(from: _dragProgress);
      }
    }
  }

  void _flipForward() {
    if (_currentPage < widget.pageCount - 1 && !_animController.isAnimating) {
      _isForward = true;
      _isDragging = true;
      _animController.forward(from: 0.0);
    }
  }

  void _flipBackward() {
    if (_currentPage > 0 && !_animController.isAnimating) {
      _isForward = false;
      _isDragging = true;
      _animController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    return GestureDetector(
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onTapUp: (details) {
        if (details.localPosition.dx > width * 0.75) {
          _flipForward();
        } else if (details.localPosition.dx < width * 0.25) {
          _flipBackward();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!_isDragging)
            widget.builder(context, _currentPage)
          else ...[
            if (_isForward)
              _buildForwardLayers(context, width, height)
            else
              _buildBackwardLayers(context, width, height),
          ],
        ],
      ),
    );
  }

  Widget _buildForwardLayers(BuildContext context, double w, double h) {
    final nextPageIndex = _currentPage + 1;
    final foldX = w * (1.0 - _dragProgress);
    final flapWidth = math.min(w * 0.28, (w - foldX) * 0.6);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Destination Page (N+1) revealed underneath
        ClipRect(
          clipper: _RectClipper(Rect.fromLTRB(foldX, 0, w, h)),
          child: widget.builder(context, nextPageIndex),
        ),

        // Drop shadow onto Destination Page
        Positioned(
          left: foldX,
          top: 0,
          width: math.min(28.0, w - foldX),
          height: h,
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0x42000000), // 26% black
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // 2. Source Page (N) unpeeled region
        ClipRect(
          clipper: _RectClipper(Rect.fromLTRB(0, 0, foldX, h)),
          child: widget.builder(context, _currentPage),
        ),

        // Crease shadow on Source Page
        Positioned(
          left: math.max(0.0, foldX - 16.0),
          top: 0,
          width: 16.0,
          height: h,
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Color(0x29000000), // 16% black
                  ],
                ),
              ),
            ),
          ),
        ),

        // 3. Dynamic Curled Flap (Back of Page N)
        if (flapWidth > 1.0)
          Positioned(
            left: foldX - flapWidth,
            top: 0,
            width: flapWidth,
            height: h,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Opaque paper base to prevent background bleeding
                  Container(
                    color: widget.paperColor.withAlpha(250),
                  ),

                  // Subtle ink show-through (Clean X-flip via setEntry, zero deprecation)
                  if (widget.enablePaperTransparency)
                    Opacity(
                      opacity: 0.04,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..setEntry(0, 0, -1.0),
                        child: widget.builder(context, _currentPage),
                      ),
                    ),

                  // Dynamic curl lighting gradient
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0x33000000), // 20% black
                          const Color(0x4DFFFFFF), // 30% white
                          widget.paperColor,
                        ],
                        stops: const [0.0, 0.35, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBackwardLayers(BuildContext context, double w, double h) {
    final prevPageIndex = _currentPage - 1;
    final foldX = w * _dragProgress;
    final flapWidth = math.min(w * 0.28, foldX * 0.6);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Current Page (N) stationary underneath
        ClipRect(
          clipper: _RectClipper(Rect.fromLTRB(foldX, 0, w, h)),
          child: widget.builder(context, _currentPage),
        ),

        // Drop shadow onto Current Page
        Positioned(
          left: foldX,
          top: 0,
          width: math.min(28.0, w - foldX),
          height: h,
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0x42000000), // 26% black
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // 2. Previous Page (N-1) peeled in from left
        ClipRect(
          clipper: _RectClipper(
              Rect.fromLTRB(0, 0, math.max(0.0, foldX - flapWidth), h)),
          child: widget.builder(context, prevPageIndex),
        ),

        // 3. Backward Curled Flap
        if (flapWidth > 1.0)
          Positioned(
            left: foldX - flapWidth,
            top: 0,
            width: flapWidth,
            height: h,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: widget.paperColor.withAlpha(250),
                  ),
                  if (widget.enablePaperTransparency)
                    Opacity(
                      opacity: 0.04,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..setEntry(0, 0, -1.0),
                        child: widget.builder(context, prevPageIndex),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.paperColor,
                          const Color(0x4DFFFFFF),
                          const Color(0x33000000),
                        ],
                        stops: const [0.0, 0.65, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RectClipper extends CustomClipper<Rect> {
  final Rect clipRect;
  _RectClipper(this.clipRect);

  @override
  Rect getClip(Size size) => clipRect;

  @override
  bool shouldReclip(_RectClipper oldClipper) => oldClipper.clipRect != clipRect;
}
