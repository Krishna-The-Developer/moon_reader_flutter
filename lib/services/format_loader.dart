import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart' as epub;
import 'package:flutter/foundation.dart';
import 'package:pdfx/pdfx.dart';

class ParsedBookContent {
  final List<String> textChunks;
  final List<Uint8List> imagePages;
  final bool isImageBook;

  ParsedBookContent({
    required this.textChunks,
    required this.imagePages,
    required this.isImageBook,
  });
}

class FormatLoader {
  static Future<ParsedBookContent> loadBook(String path, String format) async {
    final file = File(path);
    if (!await file.exists()) {
      return ParsedBookContent(
        textChunks: ["File not found: $path"],
        imagePages: [],
        isImageBook: false,
      );
    }

    // Normalize format string (.epub, EPUB, epub -> epub)
    String fmt = format.toLowerCase().replaceAll('.', '').trim();
    if (fmt.isEmpty) {
      fmt = path.split('.').last.toLowerCase().replaceAll('.', '').trim();
    }

    if (fmt == 'pdf') {
      return _loadPdf(file);
    } else if (fmt == 'cbz' || fmt == 'cbr' || fmt == 'zip') {
      return _loadCbz(file);
    } else if (fmt == 'epub') {
      return _loadEpub(file);
    } else {
      return _loadTxt(file);
    }
  }

  // 1. PDF via native PDFX visual rendering
  static Future<ParsedBookContent> _loadPdf(File file) async {
    try {
      final document = await PdfDocument.openFile(file.path);
      final List<Uint8List> pages = [];
      final count = document.pagesCount;
      for (int i = 1; i <= count; i++) {
        final page = await document.getPage(i);
        final pageImage = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );
        if (pageImage != null) {
          pages.add(pageImage.bytes);
        }
        await page.close();
      }
      await document.close();

      if (pages.isNotEmpty) {
        return ParsedBookContent(
            textChunks: [], imagePages: pages, isImageBook: true);
      }
    } catch (e) {
      debugPrint("PDF Load Error: $e");
    }

    return ParsedBookContent(
      textChunks: ["Failed to render PDF: ${file.uri.pathSegments.last}"],
      imagePages: [],
      isImageBook: false,
    );
  }

  // 2. CBZ / Comic Archive with Natural Sorting & Metadata Filtering
  static Future<ParsedBookContent> _loadCbz(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final List<Uint8List> images = [];

      final files = archive.files.where((f) {
        final n = f.name.toLowerCase();
        return f.isFile &&
            !n.contains('__macosx') &&
            !n.startsWith('.') &&
            (n.endsWith('.jpg') ||
                n.endsWith('.png') ||
                n.endsWith('.webp') ||
                n.endsWith('.jpeg'));
      }).toList();

      // Natural alphanumeric sort (page2 comes before page10)
      files.sort((a, b) => _naturalCompare(a.name, b.name));

      for (final f in files) {
        final dynamic content = f.content;
        if (content is List<int> && content.isNotEmpty) {
          images.add(Uint8List.fromList(content));
        }
      }

      if (images.isNotEmpty) {
        return ParsedBookContent(
            textChunks: [], imagePages: images, isImageBook: true);
      }
    } catch (e) {
      debugPrint("CBZ Load Error: $e");
    }

    return ParsedBookContent(
      textChunks: ["Could not extract images from comic archive."],
      imagePages: [],
      isImageBook: false,
    );
  }

  // 3. EPUB with recursive chapter traversal & HTML spine fallback
  static Future<ParsedBookContent> _loadEpub(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final book = await epub.EpubReader.readBook(bytes);
      final List<String> chunks = [];

      void extractChapter(epub.EpubChapter chap) {
        final html = chap.HtmlContent ?? '';
        final plain = _stripHtml(html);
        if (plain.isNotEmpty) {
          _splitIntoChunks(plain, chunks);
        }
        for (final sub in chap.SubChapters ?? []) {
          extractChapter(sub);
        }
      }

      for (final chap in book.Chapters ?? []) {
        extractChapter(chap);
      }

      // If chapter tree had no text, fall back to complete HTML spine
      if (chunks.isEmpty && book.Content?.Html != null) {
        for (final htmlFile in book.Content!.Html!.values) {
          final plain = _stripHtml(htmlFile.Content ?? '');
          if (plain.isNotEmpty) {
            _splitIntoChunks(plain, chunks);
          }
        }
      }

      if (chunks.isNotEmpty) {
        return ParsedBookContent(
            textChunks: chunks, imagePages: [], isImageBook: false);
      }
    } catch (e) {
      debugPrint("EPUB Load Error: $e");
    }

    return ParsedBookContent(
      textChunks: ["Unable to extract readable text from this EPUB file."],
      imagePages: [],
      isImageBook: false,
    );
  }

  // 4. Plain Text (UTF-8, Latin-1, ASCII)
  static Future<ParsedBookContent> _loadTxt(File file) async {
    try {
      final bytes = await file.readAsBytes();
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        try {
          text = latin1.decode(bytes);
        } catch (_) {
          text = String.fromCharCodes(bytes);
        }
      }

      final List<String> chunks = [];
      _splitIntoChunks(text, chunks);
      if (chunks.isEmpty) chunks.add("Empty text document.");

      return ParsedBookContent(
          textChunks: chunks, imagePages: [], isImageBook: false);
    } catch (e) {
      return ParsedBookContent(
        textChunks: ["Error opening text file: $e"],
        imagePages: [],
        isImageBook: false,
      );
    }
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(
            RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static void _splitIntoChunks(String text, List<String> targetList) {
    const chunkSize = 550; // Optimized size for single-page reading
    for (int i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize < text.length) ? i + chunkSize : text.length;
      final part = text.substring(i, end).trim();
      if (part.isNotEmpty) {
        targetList.add(part);
      }
    }
  }

  static int _naturalCompare(String a, String b) {
    final regex = RegExp(r'(\d+)|(\D+)');
    final matchesA = regex.allMatches(a).toList();
    final matchesB = regex.allMatches(b).toList();
    final count =
        matchesA.length < matchesB.length ? matchesA.length : matchesB.length;

    for (int i = 0; i < count; i++) {
      final strA = matchesA[i].group(0)!;
      final strB = matchesB[i].group(0)!;
      final numA = int.tryParse(strA);
      final numB = int.tryParse(strB);

      if (numA != null && numB != null) {
        final diff = numA.compareTo(numB);
        if (diff != 0) return diff;
      } else {
        final diff = strA.compareTo(strB);
        if (diff != 0) return diff;
      }
    }
    return a.length.compareTo(b.length);
  }
}
