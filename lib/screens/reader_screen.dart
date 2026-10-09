import 'package:flutter/material.dart';
import '../models/book_model.dart';
import '../services/progressive_document_controller.dart';
import '../widgets/page_curl_view.dart';
import '../widgets/animated_ribbon.dart';

enum ReadingMode { curl3d, horizontal, vertical }

class ReaderScreen extends StatefulWidget {
  final LocalBook book;
  final ReadingMode initialMode;

  const ReaderScreen({
    super.key,
    required this.book,
    this.initialMode = ReadingMode.curl3d,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late ProgressiveDocumentController _controller;
  late ReadingMode _currentMode;
  late int _currentPage;
  late PageController _horizontalController;
  late ScrollController _verticalController;

  bool _loading = true;
  Color _pageBgColor = const Color(0xFFF5EACB); // Authentic Warm Cream
  final Color _selectedHighlightColor =
      Colors.yellowAccent.withValues(alpha: 0.5);
  double _fontSize = 16.5;
  double _lineHeight = 1.7;

  final List<Color> _paperPalettes = const [
    Color(0xFFF5EACB), // Warm Cream
    Color(0xFFF3E5C5), // Classic Vintage Amber
    Color(0xFFFAF6EE), // Natural Soft Linen
    Color(0xFFEFE6D5), // Antique Parchment
  ];

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
    _currentPage = widget.book.lastPage;
    _horizontalController = PageController(initialPage: _currentPage);
    _verticalController = ScrollController();

    _controller = ProgressiveDocumentController(
      filePath: widget.book.filePath,
      format: widget.book.format,
    )..addListener(_onControllerUpdate);

    _initDocument();
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _initDocument() async {
    await _controller.initialize();
    if (!mounted) return;

    if (_currentPage >= _controller.totalPages) {
      _currentPage = 0;
    }

    _controller.setReadingPosition(_currentPage);

    setState(() {
      _loading = false;
      widget.book.totalPages = _controller.totalPages;
      widget.book.safeSave();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _saveProgress(int page) {
    if (_currentPage == page) return;
    setState(() => _currentPage = page);
    _controller.setReadingPosition(page);
    widget.book.lastPage = page;
    widget.book.lastRead = DateTime.now();
    widget.book.safeSave();
  }

  void _toggleBookmark() {
    setState(() {
      if (widget.book.bookmarkedPages.contains(_currentPage)) {
        widget.book.bookmarkedPages.remove(_currentPage);
      } else {
        widget.book.bookmarkedPages.add(_currentPage);
      }
      widget.book.safeSave();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_controller.isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF1B120C),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFFD4A373)),
              const SizedBox(height: 16),
              Text(
                'Opening "${widget.book.title}"...',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final isBookmarked = widget.book.bookmarkedPages.contains(_currentPage);
    final total = _controller.totalPages;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: _pageBgColor,
                child: _buildReader(total),
              ),
            ),
            AnimatedRibbonBookmark(isBookmarked: isBookmarked),
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.tune, color: Colors.white70),
                    tooltip: 'Paper & Typography',
                    onPressed: _showTypographySheet,
                  ),
                  IconButton(
                    icon: Icon(
                      isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                      color: isBookmarked ? Colors.redAccent : Colors.white70,
                    ),
                    onPressed: _toggleBookmark,
                  ),
                  PopupMenuButton<ReadingMode>(
                    icon: const Icon(Icons.auto_stories, color: Colors.white70),
                    onSelected: (mode) => setState(() => _currentMode = mode),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                          value: ReadingMode.curl3d,
                          child: Text("3D Page Curl")),
                      PopupMenuItem(
                          value: ReadingMode.horizontal,
                          child: Text("Horizontal Swipe")),
                      PopupMenuItem(
                          value: ReadingMode.vertical,
                          child: Text("Vertical Scroll")),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReader(int total) {
    if (_currentMode == ReadingMode.curl3d) {
      return RealisticPageCurl(
        pageCount: total,
        initialPage: _currentPage,
        onPageChanged: _saveProgress,
        builder: (ctx, idx) => _buildPageContent(idx, total),
      );
    } else if (_currentMode == ReadingMode.horizontal) {
      return PageView.builder(
        controller: _horizontalController,
        itemCount: total,
        onPageChanged: _saveProgress,
        itemBuilder: (ctx, idx) => _buildPageContent(idx, total),
      );
    } else {
      return ListView.builder(
        controller: _verticalController,
        itemCount: total,
        itemBuilder: (ctx, idx) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildPageContent(idx, total),
        ),
      );
    }
  }

  Widget _buildPageContent(int index, int total) {
    final page = _controller.getPage(index);
    final isHighlighted =
        widget.book.highlights.any((h) => h.startsWith("$index|"));

    return Container(
      color: isHighlighted ? _selectedHighlightColor : _pageBgColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Content or Placeholder
          if (page.status == PageStatus.ready)
            _buildReadyPage(page)
          else if (page.status == PageStatus.failed)
            _buildFailedPlaceholder(index, page.errorMessage)
          else
            _buildLoadingSkeleton(),

          // Page Number Indicator
          Positioned(
            bottom: 12,
            right: 20,
            child: Text(
              '${index + 1} / $total',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0x662B221B),
                fontFamily: 'serif',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadyPage(ReconstructedPage page) {
    if (page.isImage && page.imageBytes != null) {
      return Center(
        child: Image.memory(
          page.imageBytes!,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        ),
      );
    }

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Text(
        page.textContent ?? "",
        style: TextStyle(
          fontSize: _fontSize,
          height: _lineHeight,
          color: const Color(0xFF2B221B), // Crisp book ink
          fontFamily: 'serif',
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: const Color(0xFF8D6E63).withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Reconstructing page layout...',
            style: TextStyle(
              fontSize: 12,
              color: Color(0x772B221B),
              fontFamily: 'serif',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedPlaceholder(int index, String? error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.brown, size: 36),
          const SizedBox(height: 8),
          const Text(
            'Page layout could not be loaded',
            style: TextStyle(
                color: Color(0xFF2B221B), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5A381E)),
            onPressed: () => _controller.retryPage(index),
            icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
            label:
                const Text('Retry Page', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showTypographySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF24140A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Paper Tone',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final color in _paperPalettes)
                      GestureDetector(
                        onTap: () {
                          setState(() => _pageBgColor = color);
                          setModalState(() {});
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _pageBgColor == color
                                  ? Colors.amber
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('Font Size: ${_fontSize.toStringAsFixed(1)}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                Slider(
                  value: _fontSize,
                  min: 13.0,
                  max: 26.0,
                  activeColor: const Color(0xFFD4A373),
                  onChanged: (val) {
                    setState(() => _fontSize = val);
                    setModalState(() {});
                  },
                ),
                Text('Line Spacing: ${_lineHeight.toStringAsFixed(1)}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                Slider(
                  value: _lineHeight,
                  min: 1.3,
                  max: 2.3,
                  activeColor: const Color(0xFFD4A373),
                  onChanged: (val) {
                    setState(() => _lineHeight = val);
                    setModalState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
