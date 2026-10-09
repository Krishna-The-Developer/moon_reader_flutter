import 'dart:io';
import 'package:flutter/material.dart';
import '../models/book_model.dart';

class ShelfBookItem extends StatelessWidget {
  final LocalBook book;
  final bool isHighlighted;
  final bool showSpineOnly;
  final VoidCallback onTap;

  const ShelfBookItem({
    super.key,
    required this.book,
    required this.isHighlighted,
    required this.showSpineOnly,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, isHighlighted ? -35 : 0, 0),
      child: GestureDetector(
        onTap: onTap,
        child: showSpineOnly ? _buildBookSpine() : _buildCoverView(),
      ),
    );
  }

  Widget _buildCoverView() {
    return Container(
      width: 115,
      height: 155,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2C241E),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: isHighlighted
                ? Colors.amber.withValues(alpha: 0.7)
                : Colors.black87,
            blurRadius: isHighlighted ? 14 : 7,
            offset: const Offset(3, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            book.coverPath != null && File(book.coverPath!).existsSync()
                ? Image.file(File(book.coverPath!), fit: BoxFit.cover)
                : _buildProceduralCover(),
            // Spine Crease
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 8,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black54,
                      Colors.white10,
                      Colors.transparent
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookSpine() {
    return Container(
      width: 34,
      height: 145,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: _getSpineColor(book.title),
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(2, 3))
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: RotatedBox(
              quarterTurns: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF0E6D2),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Container(height: 1.5, color: Colors.black38)),
          Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: Container(height: 1.5, color: Colors.black38)),
        ],
      ),
    );
  }

  Widget _buildProceduralCover() {
    return Container(
      color: const Color(0xFF3E2723),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            book.format.toUpperCase(),
            style: const TextStyle(
                color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 3,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            book.author,
            maxLines: 1,
            style: const TextStyle(color: Colors.white54, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Color _getSpineColor(String text) {
    final colors = [
      const Color(0xFF4A148C),
      const Color(0xFF1B5E20),
      const Color(0xFF0D47A1),
      const Color(0xFF880E4F),
      const Color(0xFF3E2723),
    ];
    return colors[text.length % colors.length];
  }
}
