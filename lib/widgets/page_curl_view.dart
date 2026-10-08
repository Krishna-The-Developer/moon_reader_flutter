import 'dart:math' as math;
import 'package:flutter/material.dart';

class RealisticPageCurl extends StatefulWidget {
  final int pageCount;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final Widget Function(BuildContext context, int index) builder;

  const RealisticPageCurl({
    super.key,
    required this.pageCount,
    this.initialPage = 0,
    required this.onPageChanged,
    required this.builder,
  });

  @override
  State<RealisticPageCurl> createState() => _RealisticPageCurlState();
}

class _RealisticPageCurlState extends State<RealisticPageCurl> with SingleTickerProviderStateMixin {
  late int _currentPage;
  double _dragOffset = 0.0;
  late AnimationController _animController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta ?? 0;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final threshold = 80.0;

    if (_dragOffset < -threshold && _currentPage < widget.pageCount - 1) {
      // Flip Next
      _animateFlip(-1.0, () {
        setState(() {
          _currentPage++;
          _dragOffset = 0.0;
        });
        widget.onPageChanged(_currentPage);
      });
    } else if (_dragOffset > threshold && _currentPage > 0) {
      // Flip Prev
      _animateFlip(1.0, () {
        setState(() {
          _currentPage--;
          _dragOffset = 0.0;
        });
        widget.onPageChanged(_currentPage);
      });
    } else {
      // Snap Back
      _animateFlip(0.0, () {
        setState(() => _dragOffset = 0.0);
      });
    }
  }

  void _animateFlip(double target, VoidCallback onComplete) {
    _animation = Tween<double>(begin: _dragOffset, end: target == 0 ? 0 : target * 300).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    )..addListener(() => setState(() => _dragOffset = _animation.value));

    _animController.forward(from: 0).then((_) {
      onComplete();
      _animController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pageCount == 0) return const SizedBox();

    final width = MediaQuery.of(context).size.width;
    final progress = (_dragOffset / (width > 0 ? width : 400)).clamp(-1.0, 1.0);
    final angle = progress * (math.pi / 2.2);

    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Underlying Next Page
          if (progress < 0 && _currentPage < widget.pageCount - 1)
            widget.builder(context, _currentPage + 1),

          // Underlying Previous Page
          if (progress > 0 && _currentPage > 0)
            widget.builder(context, _currentPage - 1),

          // Current Page with 3D Curl Transform & Spine Shadow
          Transform(
            alignment: progress < 0 ? Alignment.centerRight : Alignment.centerLeft,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // 3D Perspective Depth
              ..rotateY(angle),
            child: Stack(
              children: [
                widget.builder(context, _currentPage),
                // Spine crease shadow
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withOpacity((progress.abs() * 0.45).clamp(0.0, 0.45)),
                            Colors.transparent,
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}