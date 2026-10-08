import 'dart:io';
import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart' as epub;
import 'package:path_provider/path_provider.dart';
import '../models/book_model.dart';

class MetadataScanner {
  static Future<LocalBook> scanAndCreateBook(File file) async {
    final fileName = file.uri.pathSegments.last;
    final extension = fileName.split('.').last.toLowerCase();
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    String title = _cleanTitle(fileName);
    String author = "Local Author";
    String? coverPath;

    final appDir = await getApplicationDocumentsDirectory();
    final coversDir = Directory('${appDir.path}/covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    try {
      if (extension == 'epub') {
        final bytes = await file.readAsBytes();
        final epubBook = await epub.EpubReader.readBook(bytes);

        if (epubBook.Title != null && epubBook.Title!.trim().isNotEmpty) {
          title = epubBook.Title!.trim();
        }
        if (epubBook.Author != null && epubBook.Author!.trim().isNotEmpty) {
          author = epubBook.Author!.trim();
        }

        if (epubBook.Content?.Images != null && epubBook.Content!.Images!.isNotEmpty) {
          final imagesMap = epubBook.Content!.Images!;
          epub.EpubByteContentFile? coverEntry;

          for (final key in imagesMap.keys) {
            if (key.toLowerCase().contains('cover')) {
              coverEntry = imagesMap[key];
              break;
            }
          }
          coverEntry ??= imagesMap.values.first;

          if (coverEntry.Content != null && coverEntry.Content!.isNotEmpty) {
            final coverFile = File('${coversDir.path}/$id.png');
            await coverFile.writeAsBytes(coverEntry.Content!);
            coverPath = coverFile.path;
          }
        }
      } else if (extension == 'cbz') {
        final bytes = await file.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);

        final imageFiles = archive.files.where((f) {
          final n = f.name.toLowerCase();
          return f.isFile &&
              (n.endsWith('.jpg') || n.endsWith('.png') || n.endsWith('.jpeg') || n.endsWith('.webp'));
        }).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        if (imageFiles.isNotEmpty) {
          final firstImage = imageFiles.first;
          final dynamic content = firstImage.content;
          if (content is List<int> && content.isNotEmpty) {
            final coverFile = File('${coversDir.path}/$id.jpg');
            await coverFile.writeAsBytes(content);
            coverPath = coverFile.path;
          }
        }
        author = "Graphic Novel / Comic";
      }
    } catch (_) {
      // Fallback cleanly on corrupt archive headers
    }

    return LocalBook(
      id: id,
      title: title,
      filePath: file.path,
      format: extension,
      author: author,
      coverPath: coverPath,
    );
  }

  static String _cleanTitle(String raw) {
    String name = raw.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'[_+\-]'), ' ');
    return name.trim().isEmpty ? "Untitled Book" : name.trim();
  }
}