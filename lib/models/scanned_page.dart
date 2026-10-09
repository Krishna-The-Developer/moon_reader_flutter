import 'package:flutter/material.dart';

enum ScannedBlockType { heading, subheading, paragraph }

class ScannedBlock {
  String text;
  final ScannedBlockType type;
  final TextAlign alignment;
  final double relativeTopGap;

  ScannedBlock({
    required this.text,
    required this.type,
    this.alignment = TextAlign.left,
    this.relativeTopGap = 12.0,
  });
}

class ScannedPageData {
  final String imagePath;
  final List<ScannedBlock> blocks;
  double fontSize;
  double lineSpacing;
  Color paperColor;

  ScannedPageData({
    required this.imagePath,
    required this.blocks,
    this.fontSize = 16.5,
    this.lineSpacing = 1.7,
    this.paperColor = const Color(0xFFF5EACB), // Warm cream book paper
  });

  String get fullText => blocks.map((b) => b.text).join('\n\n');
}
