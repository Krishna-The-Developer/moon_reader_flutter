import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart' as epub;

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

    // 2. EPUB
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

    // 3. PDF Text Stream Parser
    if (format == 'pdf') {
      final bytes = await file.readAsBytes();
      final buffer = StringBuffer();
      final content =
          String.fromCharCodes(bytes.where((b) => (b >= 32 && b <= 126) || b == 10 || b == 13));

      // Fixed Regex: Clean double-quoted raw string
      final regex = RegExp(r"\(([^)]+)\)");
      for (final m in regex.allMatches(content)) {
        final str = m.group(1);
        if (str != null && str.trim().isNotEmpty) {
          buffer.write('$str ');
        }
      }

      final extracted = buffer.toString().trim();
      final List<String> chunks = [];
      if (extracted.isNotEmpty) {
        _splitIntoChunks(extracted, chunks);
      } else {
        chunks.add("PDF: ${file.uri.pathSegments.last}\n\nPure text streams could not be parsed.\n(For best reading experience on Kali, use EPUB, TXT, or CBZ format).");
      }
      return ParsedBookContent(textChunks: chunks, imagePages: [], isImageBook: false);
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
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
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