import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../models/scanned_page.dart';

class OcrScannerService {
  static final ImagePicker _picker = ImagePicker();

  /// Captures an image from Camera or picks from Gallery
  static Future<File?> pickPageImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 92,
      );
      if (picked != null) {
        return File(picked.path);
      }
    } catch (e) {
      debugPrint('Image picker error: $e');
    }
    return null;
  }

  /// Runs ML Kit OCR and reconstructs page layout (Headings, Paragraphs, Alignment)
  static Future<ScannedPageData?> processPage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final recognizedText = await textRecognizer.processImage(inputImage);
      if (recognizedText.blocks.isEmpty) {
        return null;
      }

      // Calculate median line height to distinguish headings from normal paragraphs
      final List<double> lineHeights = [];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          lineHeights.add(line.boundingBox.height);
        }
      }

      lineHeights.sort();
      final double medianHeight =
          lineHeights.isNotEmpty ? lineHeights[lineHeights.length ~/ 2] : 16.0;

      // Sort blocks top-to-bottom based on Y coordinate
      final sortedBlocks = List<TextBlock>.from(recognizedText.blocks)
        ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

      final List<ScannedBlock> reconstructedBlocks = [];
      double lastBottom = 0.0;

      for (final block in sortedBlocks) {
        final text = block.text.trim();
        if (text.isEmpty) continue;

        final double blockLineHeight = block.lines.isNotEmpty
            ? block.lines.first.boundingBox.height
            : medianHeight;

        // Classify Block Type
        ScannedBlockType type = ScannedBlockType.paragraph;
        if (blockLineHeight > medianHeight * 1.38) {
          type = ScannedBlockType.heading;
        } else if (blockLineHeight > medianHeight * 1.18 && text.length < 80) {
          type = ScannedBlockType.subheading;
        }

        // Detect Alignment: Center vs Left
        TextAlign align = TextAlign.left;
        if (type != ScannedBlockType.paragraph && text.length < 50) {
          align = TextAlign.center;
        }

        // Compute relative gap
        final double gap = lastBottom == 0.0
            ? 8.0
            : (block.boundingBox.top - lastBottom).clamp(8.0, 32.0);
        lastBottom = block.boundingBox.bottom;

        reconstructedBlocks.add(
          ScannedBlock(
            text: text,
            type: type,
            alignment: align,
            relativeTopGap: gap,
          ),
        );
      }

      return ScannedPageData(
        imagePath: imageFile.path,
        blocks: reconstructedBlocks,
      );
    } catch (e) {
      debugPrint('OCR processing error: $e');
      return null;
    } finally {
      await textRecognizer.close();
    }
  }
}
