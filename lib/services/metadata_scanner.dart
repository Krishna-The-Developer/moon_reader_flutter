import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import '../models/book_model.dart';

class MetadataScanner {
  static Future<LocalBook> scanAndCreateBook(File file) async {
    final filePath = file.path;
    final extension = _getExtension(filePath);

    if (extension == '.epub') {
      return await _scanEpub(file);
    } else if (extension == '.pdf') {
      return _scanPdf(file);
    } else if (extension == '.cbz') {
      return _scanCbz(file);
    } else {
      return _scanTxt(file);
    }
  }

  // Alias for backward compatibility
  static Future<LocalBook> scanFile(File file) => scanAndCreateBook(file);

  static Future<LocalBook> _scanEpub(File file) async {
    String? title;
    String? author;

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 1. Locate OPF file path from META-INF/container.xml
      String opfPath = '';
      final containerFile = archive.findFile('META-INF/container.xml');
      if (containerFile != null) {
        final containerXml = utf8.decode(
          containerFile.content as List<int>,
          allowMalformed: true,
        );
        final match = RegExp(
          r'full-path\s*=\s*["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        ).firstMatch(containerXml);
        if (match != null) {
          opfPath = match.group(1) ?? '';
        }
      }

      // 2. Fallback search for any .opf file if container.xml is missing or path invalid
      ArchiveFile? opfFile;
      if (opfPath.isNotEmpty) {
        opfFile = archive.findFile(opfPath);
      }
      if (opfFile == null) {
        for (final f in archive.files) {
          if (f.name.toLowerCase().endsWith('.opf')) {
            opfFile = f;
            break;
          }
        }
      }

      // 3. Parse OPF metadata section
      if (opfFile != null) {
        final opfContent = utf8.decode(
          opfFile.content as List<int>,
          allowMalformed: true,
        );

        // Extract Title (<dc:title ...>...</dc:title>)
        final titleMatch = RegExp(
          r'<dc:title[^>]*>([\s\S]*?)<\/dc:title>',
          caseSensitive: false,
        ).firstMatch(opfContent);
        if (titleMatch != null) {
          title = _cleanXmlText(titleMatch.group(1));
        }

        // Extract Creator / Author (<dc:creator ...>...</dc:creator>)
        final authorMatch = RegExp(
          r'<dc:creator[^>]*>([\s\S]*?)<\/dc:creator>',
          caseSensitive: false,
        ).firstMatch(opfContent);
        if (authorMatch != null) {
          author = _cleanXmlText(authorMatch.group(1));
        }
      }
    } catch (_) {
      // Archive error handling falls back to filename
    }

    final resolvedTitle = _resolveTitle(title, file.path);
    final resolvedAuthor = (author != null && author.trim().isNotEmpty)
        ? author.trim()
        : 'Unknown Author';

    return LocalBook(
      id: file.path,
      title: resolvedTitle,
      author: resolvedAuthor,
      filePath: file.path,
      format: 'epub',
      lastRead: DateTime.now(),
      lastPage: 0,
      totalPages: 1,
      bookmarkedPages: [],
      highlights: [],
    );
  }

  static LocalBook _scanPdf(File file) {
    final title = _resolveTitle(null, file.path);
    return LocalBook(
      id: file.path,
      title: title,
      author: 'PDF Document',
      filePath: file.path,
      format: 'pdf',
      lastRead: DateTime.now(),
      lastPage: 0,
      totalPages: 1,
      bookmarkedPages: [],
      highlights: [],
    );
  }

  static LocalBook _scanCbz(File file) {
    final title = _resolveTitle(null, file.path);
    return LocalBook(
      id: file.path,
      title: title,
      author: 'Graphic Novel',
      filePath: file.path,
      format: 'cbz',
      lastRead: DateTime.now(),
      lastPage: 0,
      totalPages: 1,
      bookmarkedPages: [],
      highlights: [],
    );
  }

  static LocalBook _scanTxt(File file) {
    final title = _resolveTitle(null, file.path);
    return LocalBook(
      id: file.path,
      title: title,
      author: 'Plain Text',
      filePath: file.path,
      format: 'txt',
      lastRead: DateTime.now(),
      lastPage: 0,
      totalPages: 1,
      bookmarkedPages: [],
      highlights: [],
    );
  }

  static String _resolveTitle(String? rawTitle, String filePath) {
    if (rawTitle != null && rawTitle.trim().isNotEmpty) {
      final cleaned = rawTitle.trim();
      if (cleaned.toLowerCase() != 'unknown') {
        return cleaned;
      }
    }

    // Pure Dart filename extractor (zero external package dependency)
    final baseName = _basenameWithoutExtension(filePath);
    final formatted = baseName
        .replaceAll(RegExp(r'[\-_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return formatted.isNotEmpty ? formatted : 'Unknown';
  }

  static String _cleanXmlText(String? raw) {
    if (raw == null) return '';
    return raw
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _basenameWithoutExtension(String filePath) {
    final fileName =
        filePath.split(Platform.pathSeparator).last.split('/').last;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex != -1) {
      return fileName.substring(0, dotIndex);
    }
    return fileName;
  }

  static String _getExtension(String filePath) {
    final dotIndex = filePath.lastIndexOf('.');
    if (dotIndex != -1) {
      return filePath.substring(dotIndex).toLowerCase();
    }
    return '';
  }
}
