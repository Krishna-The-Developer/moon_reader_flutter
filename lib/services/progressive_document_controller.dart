import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart' as epub;
import 'package:flutter/foundation.dart';
import 'package:pdfx/pdfx.dart';

enum PageStatus { notRequested, loading, ready, failed }

class ReconstructedPage {
  final int index;
  final PageStatus status;
  final Uint8List? imageBytes;
  final String? textContent;
  final bool isImage;
  final String? errorMessage;

  const ReconstructedPage({
    required this.index,
    required this.status,
    this.imageBytes,
    this.textContent,
    this.isImage = false,
    this.errorMessage,
  });

  ReconstructedPage copyWith({
    PageStatus? status,
    Uint8List? imageBytes,
    String? textContent,
    bool? isImage,
    String? errorMessage,
  }) {
    return ReconstructedPage(
      index: index,
      status: status ?? this.status,
      imageBytes: imageBytes ?? this.imageBytes,
      textContent: textContent ?? this.textContent,
      isImage: isImage ?? this.isImage,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Bounded LRU Cache & Demand-Driven Progressive Loading Controller
class ProgressiveDocumentController extends ChangeNotifier {
  final String filePath;
  final String format;
  final int maxCacheSize;

  int _totalPages = 1;
  int get totalPages => _totalPages;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isImageBook = false;
  bool get isImageBook => _isImageBook;

  String? _initError;
  String? get initError => _initError;

  // Bounded page memory cache
  final Map<int, ReconstructedPage> _cache = {};
  final List<int> _lruOrder = [];

  // Active document handles
  PdfDocument? _pdfDoc;
  Archive? _cbzArchive;
  List<ArchiveFile>? _cbzImageFiles;
  final List<String> _textChunks = [];

  int _currentReadingIndex = 0;
  final Set<int> _activeLoading = {};
  bool _isDisposed = false;

  ProgressiveDocumentController({
    required this.filePath,
    required this.format,
    this.maxCacheSize = 25,
  });

  /// Stage A: Fast Header Scan & Initialization (<50ms)
  Future<void> initialize() async {
    final file = File(filePath);
    if (!await file.exists()) {
      _initError = "File not found: $filePath";
      _isInitialized = true;
      notifyListeners();
      return;
    }

    String fmt = format.toLowerCase().replaceAll('.', '').trim();
    if (fmt.isEmpty) {
      fmt = filePath.split('.').last.toLowerCase().replaceAll('.', '').trim();
    }

    try {
      if (fmt == 'pdf') {
        _isImageBook = true;
        _pdfDoc = await PdfDocument.openFile(filePath);
        _totalPages = _pdfDoc!.pagesCount > 0 ? _pdfDoc!.pagesCount : 1;
      } else if (fmt == 'cbz' || fmt == 'cbr' || fmt == 'zip') {
        _isImageBook = true;
        final bytes = await file.readAsBytes();
        _cbzArchive = ZipDecoder().decodeBytes(bytes);
        _cbzImageFiles = _cbzArchive!.files.where((f) {
          final n = f.name.toLowerCase();
          return f.isFile &&
              !n.contains('__macosx') &&
              !n.startsWith('.') &&
              (n.endsWith('.jpg') ||
                  n.endsWith('.png') ||
                  n.endsWith('.webp') ||
                  n.endsWith('.jpeg'));
        }).toList();
        _cbzImageFiles!.sort((a, b) => a.name.compareTo(b.name));
        _totalPages = _cbzImageFiles!.isNotEmpty ? _cbzImageFiles!.length : 1;
      } else if (fmt == 'epub') {
        _isImageBook = false;
        await _parseEpubStructure(file);
      } else {
        _isImageBook = false;
        await _parsePlainText(file);
      }
    } catch (e) {
      _initError = "Initialization error: $e";
      _totalPages = 1;
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Fast semantic parsing for EPUB into paginated chunks
  Future<void> _parseEpubStructure(File file) async {
    final bytes = await file.readAsBytes();
    try {
      final book = await epub.EpubReader.readBook(bytes);
      for (final chap in book.Chapters ?? []) {
        final plain = _stripHtml(chap.HtmlContent ?? '');
        if (plain.isNotEmpty) _chunkText(plain, _textChunks);
        for (final sub in chap.SubChapters ?? []) {
          final subPlain = _stripHtml(sub.HtmlContent ?? '');
          if (subPlain.isNotEmpty) _chunkText(subPlain, _textChunks);
        }
      }
      if (_textChunks.isEmpty && book.Content?.Html != null) {
        for (final h in book.Content!.Html!.values) {
          final plain = _stripHtml(h.Content ?? '');
          if (plain.isNotEmpty) _chunkText(plain, _textChunks);
        }
      }
    } catch (_) {}

    // Fallback: Raw XHTML extraction from ZIP
    if (_textChunks.isEmpty) {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive.files) {
        final n = f.name.toLowerCase();
        if (f.isFile && (n.endsWith('.xhtml') || n.endsWith('.html'))) {
          String raw = "";
          if (f.content is List<int>) {
            raw = utf8.decode(f.content as List<int>, allowMalformed: true);
          } else if (f.rawContent != null) {
            raw =
                utf8.decode(f.rawContent!.toUint8List(), allowMalformed: true);
          }
          final plain = _stripHtml(raw);
          if (plain.isNotEmpty) _chunkText(plain, _textChunks);
        }
      }
    }

    if (_textChunks.isEmpty) {
      _textChunks.add("Unable to parse text from EPUB document.");
    }
    _totalPages = _textChunks.length;
  }

  Future<void> _parsePlainText(File file) async {
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
    _chunkText(text, _textChunks);
    if (_textChunks.isEmpty) _textChunks.add("Empty document.");
    _totalPages = _textChunks.length;
  }

  /// Retrieve page from memory or kick off demand-driven load
  ReconstructedPage getPage(int index) {
    if (_cache.containsKey(index)) {
      _recordAccess(index);
      return _cache[index]!;
    }

    // Schedule high-priority retrieval if not already active
    _schedulePageLoad(index, highPriority: true);

    return ReconstructedPage(
      index: index,
      status: PageStatus.loading,
      isImage: _isImageBook,
    );
  }

  /// Stages B, C & D: Update viewport position and preload nearby window
  void setReadingPosition(int index) {
    _currentReadingIndex = index;

    // High priority: Current page, next page, previous page
    _schedulePageLoad(index, highPriority: true);
    if (index + 1 < _totalPages) {
      _schedulePageLoad(index + 1, highPriority: true);
    }
    if (index - 1 >= 0) _schedulePageLoad(index - 1, highPriority: false);

    // Lookahead prefetch: next batch
    for (int offset = 2; offset <= 4; offset++) {
      final forward = index + offset;
      if (forward < _totalPages) {
        _schedulePageLoad(forward, highPriority: false);
      }
    }

    _enforceCacheBounds();
  }

  void _schedulePageLoad(int index, {required bool highPriority}) {
    if (index < 0 || index >= _totalPages || _isDisposed) return;
    if (_cache.containsKey(index) &&
        _cache[index]!.status == PageStatus.ready) {
      return;
    }
    if (_activeLoading.contains(index)) return;

    _activeLoading.add(index);

    // Asynchronous background isolate/queue execution
    Future.microtask(() async {
      if (_isDisposed) return;
      try {
        ReconstructedPage page;
        if (_pdfDoc != null) {
          page = await _renderPdfPage(index);
        } else if (_cbzImageFiles != null) {
          page = await _extractCbzPage(index);
        } else {
          page = _extractTextPage(index);
        }

        if (!_isDisposed) {
          _cache[index] = page;
          _recordAccess(index);
          _activeLoading.remove(index);
          notifyListeners();
        }
      } catch (e) {
        if (!_isDisposed) {
          _cache[index] = ReconstructedPage(
            index: index,
            status: PageStatus.failed,
            errorMessage: e.toString(),
            isImage: _isImageBook,
          );
          _activeLoading.remove(index);
          notifyListeners();
        }
      }
    });
  }

  Future<ReconstructedPage> _renderPdfPage(int index) async {
    final pageNum = index + 1;
    final page = await _pdfDoc!.getPage(pageNum);
    final rendered = await page.render(
      width: page.width * 2,
      height: page.height * 2,
      format: PdfPageImageFormat.jpeg,
      backgroundColor: '#FFFFFF',
    );
    await page.close();

    if (rendered != null) {
      return ReconstructedPage(
        index: index,
        status: PageStatus.ready,
        imageBytes: rendered.bytes,
        isImage: true,
      );
    }
    throw Exception("Page rendering produced null output");
  }

  Future<ReconstructedPage> _extractCbzPage(int index) async {
    if (index >= _cbzImageFiles!.length) {
      throw Exception("CBZ page out of bounds");
    }
    final file = _cbzImageFiles![index];
    Uint8List? bytes;
    if (file.content is List<int>) {
      bytes = Uint8List.fromList(file.content as List<int>);
    } else if (file.rawContent != null) {
      bytes = file.rawContent!.toUint8List();
    }

    if (bytes != null && bytes.isNotEmpty) {
      return ReconstructedPage(
        index: index,
        status: PageStatus.ready,
        imageBytes: bytes,
        isImage: true,
      );
    }
    throw Exception("Failed to extract CBZ image bytes");
  }

  ReconstructedPage _extractTextPage(int index) {
    if (index < _textChunks.length) {
      return ReconstructedPage(
        index: index,
        status: PageStatus.ready,
        textContent: _textChunks[index],
        isImage: false,
      );
    }
    return ReconstructedPage(
      index: index,
      status: PageStatus.ready,
      textContent: "End of document.",
      isImage: false,
    );
  }

  void retryPage(int index) {
    _cache.remove(index);
    _activeLoading.remove(index);
    _schedulePageLoad(index, highPriority: true);
  }

  void _recordAccess(int index) {
    _lruOrder.remove(index);
    _lruOrder.add(index);
  }

  /// Evict pages furthest from current reading index when exceeding maxCacheSize
  void _enforceCacheBounds() {
    if (_cache.length <= maxCacheSize) return;

    final candidates =
        _cache.keys.where((k) => (k - _currentReadingIndex).abs() > 3).toList();
    candidates.sort((a, b) => (b - _currentReadingIndex)
        .abs()
        .compareTo((a - _currentReadingIndex).abs()));

    for (final evictIndex in candidates) {
      if (_cache.length <= maxCacheSize) break;
      _cache.remove(evictIndex);
      _lruOrder.remove(evictIndex);
    }
  }

  static String _stripHtml(String html) {
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
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static void _chunkText(String text, List<String> targetList) {
    const targetLength = 650;
    int start = 0;
    while (start < text.length) {
      if (start + targetLength >= text.length) {
        final remaining = text.substring(start).trim();
        if (remaining.isNotEmpty) targetList.add(remaining);
        break;
      }
      int end = start + targetLength;
      int breakIndex = text.lastIndexOf('\n\n', end);
      if (breakIndex <= start + 250) {
        breakIndex = text.lastIndexOf(RegExp(r'[.!?]\s'), end);
      }
      if (breakIndex <= start + 200) {
        breakIndex = text.lastIndexOf(' ', end);
      }
      if (breakIndex <= start) {
        breakIndex = end;
      }
      final chunk = text.substring(start, breakIndex).trim();
      if (chunk.isNotEmpty) targetList.add(chunk);
      start = breakIndex + 1;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pdfDoc?.close();
    _cache.clear();
    _lruOrder.clear();
    _activeLoading.clear();
    super.dispose();
  }
}
