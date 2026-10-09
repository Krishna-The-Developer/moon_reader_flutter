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
        textChunks: ["File not found at path: $path"],
        imagePages: [],
        isImageBook: false,
      );
    }

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

  // 1. PDF via native visual rendering
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
      textChunks: ["Could not render PDF document."],
      imagePages: [],
      isImageBook: false,
    );
  }

  // 2. CBZ / Comic with Stream-Safe Byte Extraction
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
                n.endsWith('.jpeg') ||
                n.endsWith('.gif'));
      }).toList();

      files.sort((a, b) => _naturalCompare(a.name, b.name));

      for (final f in files) {
        Uint8List? imgBytes;
        if (f.content is List<int>) {
          imgBytes = Uint8List.fromList(f.content as List<int>);
        } else if (f.rawContent != null) {
          imgBytes = f.rawContent!.toUint8List();
        }

        if (imgBytes != null && imgBytes.isNotEmpty) {
          images.add(imgBytes);
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
      textChunks: ["Comic archive does not contain readable images."],
      imagePages: [],
      isImageBook: false,
    );
  }

  // 3. EPUB with Primary Parser + Raw ZIP Extraction Fallback
  static Future<ParsedBookContent> _loadEpub(File file) async {
    final List<String> chunks = [];
    final bytes = await file.readAsBytes();

    // Primary: epubx package parsing
    try {
      final book = await epub.EpubReader.readBook(bytes);

      void extractChapter(epub.EpubChapter chap) {
        final html = chap.HtmlContent ?? '';
        final plain = _cleanHtmlPreservingParagraphs(html);
        if (plain.isNotEmpty) {
          _smartChunkText(plain, chunks);
        }
        for (final sub in chap.SubChapters ?? []) {
          extractChapter(sub);
        }
      }

      for (final chap in book.Chapters ?? []) {
        extractChapter(chap);
      }

      if (chunks.isEmpty && book.Content?.Html != null) {
        final htmlFiles = book.Content!.Html!.values.toList();
        for (final hf in htmlFiles) {
          final plain = _cleanHtmlPreservingParagraphs(hf.Content ?? '');
          if (plain.isNotEmpty) {
            _smartChunkText(plain, chunks);
          }
        }
      }
    } catch (e) {
      debugPrint("epubx failed, switching to raw zip fallback: $e");
    }

    // Fallback: Direct Zip extraction for non-standard/complex EPUBs
    if (chunks.isEmpty) {
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        final htmlFiles = archive.files.where((f) {
          final n = f.name.toLowerCase();
          return f.isFile &&
              (n.endsWith('.xhtml') ||
                  n.endsWith('.html') ||
                  n.endsWith('.htm')) &&
              !n.contains('toc') &&
              !n.contains('nav');
        }).toList();

        htmlFiles.sort((a, b) => _naturalCompare(a.name, b.name));

        for (final f in htmlFiles) {
          String rawHtml = "";
          if (f.content is List<int>) {
            rawHtml = utf8.decode(f.content as List<int>, allowMalformed: true);
          } else if (f.rawContent != null) {
            rawHtml =
                utf8.decode(f.rawContent!.toUint8List(), allowMalformed: true);
          }

          final plain = _cleanHtmlPreservingParagraphs(rawHtml);
          if (plain.isNotEmpty) {
            _smartChunkText(plain, chunks);
          }
        }
      } catch (e) {
        debugPrint("Raw EPUB Zip fallback error: $e");
      }
    }

    if (chunks.isNotEmpty) {
      return ParsedBookContent(
          textChunks: chunks, imagePages: [], isImageBook: false);
    }

    return ParsedBookContent(
      textChunks: [
        "Unable to read text from this EPUB book. The file may be DRM-protected or corrupted."
      ],
      imagePages: [],
      isImageBook: false,
    );
  }

  // 4. TXT with Multi-Encoding Safety
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
      _smartChunkText(text, chunks);
      if (chunks.isEmpty) chunks.add("Empty document.");

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

  // --- HTML Cleaning with Paragraph & Heading Preservation ---
  static String _cleanHtmlPreservingParagraphs(String html) {
    if (html.isEmpty) return "";

    return html
        .replaceAll(
            RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'</(p|div|h[1-6]|li|tr)>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<(br|hr)[^>]*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '…')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  // --- Smart Chunking: Never cuts words in half, balances page height ---
  static void _smartChunkText(String text, List<String> targetList) {
    const targetLength = 680;
    int start = 0;

    while (start < text.length) {
      if (start + targetLength >= text.length) {
        final remaining = text.substring(start).trim();
        if (remaining.isNotEmpty) targetList.add(remaining);
        break;
      }

      int end = start + targetLength;
      // Search for paragraph break first
      int breakIndex = text.lastIndexOf('\n\n', end);
      if (breakIndex <= start + 250) {
        // Search for sentence end
        breakIndex = text.lastIndexOf(RegExp(r'[.!?]\s'), end);
      }
      if (breakIndex <= start + 200) {
        // Search for space (word boundary)
        breakIndex = text.lastIndexOf(' ', end);
      }
      if (breakIndex <= start) {
        breakIndex = end;
      }

      final chunk = text.substring(start, breakIndex).trim();
      if (chunk.isNotEmpty) {
        targetList.add(chunk);
      }
      start = breakIndex + 1;
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
