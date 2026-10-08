import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart' as epub;
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

    // 1. Comic / CBZ
    if (format == 'cbz') {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final List<Uint8List> images = [];

      final files = archive.files.where((f) {
        final n = f.name.toLowerCase();
        return f.isFile &&
            (n.endsWith('.jpg') || n.endsWith('.png') || n.endsWith('.webp') || n.endsWith('.jpeg'));
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      for (final f in files) {
        final dynamic content = f.content;
        if (content is List<int> && content.isNotEmpty) {
          images.add(Uint8List.fromList(content));
        }
      }
      return ParsedBookContent(textChunks: [], imagePages: images, isImageBook: true);
    }

    // 2. EPUB (Clean text extraction without HTML/CSS junk)
    if (format == 'epub') {
      final bytes = await file.readAsBytes();
      final book = await epub.EpubReader.readBook(bytes);
      final List<String> paragraphs = [];

      for (final chap in book.Chapters ?? []) {
        final html = chap.HtmlContent ?? '';
        final plain = _stripHtml(html);
        if (plain.isNotEmpty) {
          _splitIntoChunks(plain, paragraphs);
        }
      }

      if (paragraphs.isEmpty && book.Content?.Html != null) {
        for (final htmlFile in book.Content!.Html!.values) {
          final plain = _stripHtml(htmlFile.Content ?? '');
          if (plain.isNotEmpty) {
            _splitIntoChunks(plain, paragraphs);
          }
        }
      }

      if (paragraphs.isEmpty) {
        paragraphs.add("Empty EPUB file or unreadable formatting.");
      }

      return ParsedBookContent(textChunks: paragraphs, imagePages: [], isImageBook: false);
    }

    // 3. PDF Native Visual Rendering via PDFX (Crisp pages, zero gibberish)
    if (format == 'pdf') {
      try {
        final document = await PdfDocument.openFile(path);
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
          return ParsedBookContent(textChunks: [], imagePages: pages, isImageBook: true);
        }
      } catch (_) {}

      return ParsedBookContent(
        textChunks: ["Could not parse PDF pages: ${file.uri.pathSegments.last}"],
        imagePages: [],
        isImageBook: false,
      );
    }

    // 4. Plain Text (TXT)
    final bytes = await file.readAsBytes();
    String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      text = String.fromCharCodes(bytes);
    }

    final List<String> chunks = [];
    _splitIntoChunks(text, chunks);
    if (chunks.isEmpty) chunks.add("Empty text document.");

    return ParsedBookContent(textChunks: chunks, imagePages: [], isImageBook: false);
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
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
    const chunkSize = 800;
    for (int i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize < text.length) ? i + chunkSize : text.length;
      targetList.add(text.substring(i, end).trim());
    }
  }
}
