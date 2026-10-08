import 'package:flutter/material.dart';
import '../models/book_model.dart';
import '../services/format_loader.dart';
import '../widgets/animated_ribbon.dart';
import '../widgets/page_curl_view.dart';

enum ReadingMode { curl3d, horizontal, vertical }

class ReaderScreen extends StatefulWidget {
  final LocalBook book;
  final ReadingMode initialMode;

  const ReaderScreen({super.key, required this.book, this.initialMode = ReadingMode.curl3d});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late ReadingMode _currentMode;
  late PageController _horizontalController;
  final ScrollController _verticalController = ScrollController();

  ParsedBookContent? _content;
  bool _loading = true;
  int _currentPage = 0;
  final Color _pageBgColor = const Color(0xFFF7F1E5); // Sepia
  final Color _textColor = const Color(0xFF2B251F);
  Color _selectedHighlightColor = Colors.yellowAccent.withOpacity(0.5);

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
    _currentPage = widget.book.lastPage;
    _horizontalController = PageController(initialPage: _currentPage);
    _loadBook();
  }

  Future<void> _loadBook() async {
    final parsed = await FormatLoader.loadBook(widget.book.filePath, widget.book.format);
    setState(() {
      _content = parsed;
      _loading = false;
      widget.book.totalPages = parsed.isImageBook ? parsed.imagePages.length : parsed.textChunks.length;
      widget.book.safeSave();
    });
  }

  void _saveProgress(int page) {
    setState(() => _currentPage = page);
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

  void _showTextActions(int index) {
    if (_content == null || _content!.isImageBook) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222222),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.brush, color: _selectedHighlightColor),
                title: const Text("Highlight Paragraph with Active Color"),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    final highlightKey = "$index|${_selectedHighlightColor.value}";
                    if (!widget.book.highlights.contains(highlightKey)) {
                      widget.book.highlights.add(highlightKey);
                      widget.book.safeSave();
                    }
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.amber),
                title: const Text("Edit Page Content (Fix Mistakes)"),
                onTap: () {
                  Navigator.pop(ctx);
                  _editTextDialog(index);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _editTextDialog(int index) {
    final controller = TextEditingController(text: _content!.textChunks[index]);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF262626),
        title: const Text("Edit Page Content", style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          maxLines: 10,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _content!.textChunks[index] = controller.text;
              });
              Navigator.pop(ctx);
            },
            child: const Text("Save Changes"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _content == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    final isBookmarked = widget.book.bookmarkedPages.contains(_currentPage);
    final total = _content!.isImageBook ? _content!.imagePages.length : _content!.textChunks.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: 1 / 1.414,
                child: Container(
                  color: _pageBgColor,
                  child: _buildReader(total),
                ),
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
                  _buildColorPickerDot(Colors.yellowAccent.withOpacity(0.5)),
                  _buildColorPickerDot(Colors.greenAccent.withOpacity(0.5)),
                  _buildColorPickerDot(Colors.pinkAccent.withOpacity(0.5)),
                  _buildColorPickerDot(Colors.lightBlueAccent.withOpacity(0.5)),
                  const SizedBox(width: 8),
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
                      PopupMenuItem(value: ReadingMode.curl3d, child: Text("3D Page Curl")),
                      PopupMenuItem(value: ReadingMode.horizontal, child: Text("Horizontal Swipe")),
                      PopupMenuItem(value: ReadingMode.vertical, child: Text("Vertical Scroll")),
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
          padding: const EdgeInsets.only(bottom: 20),
          child: _buildPageContent(idx, total),
        ),
      );
    }
  }

  Widget _buildPageContent(int index, int total) {
    final isHighlighted = widget.book.highlights.any((h) => h.startsWith("$index|"));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      color: isHighlighted ? _selectedHighlightColor : _pageBgColor,
      child: Stack(
        children: [
          _content!.isImageBook
              ? Center(child: Image.memory(_content!.imagePages[index], fit: BoxFit.contain))
              : GestureDetector(
                  onLongPress: () => _showTextActions(index),
                  child: SelectableText(
                    _content!.textChunks[index],
                    style: TextStyle(
                      fontSize: 16.5,
                      height: 1.7,
                      color: _textColor,
                      fontFamily: 'serif',
                    ),
                  ),
                ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Text(
              '${index + 1} / $total',
              style: TextStyle(fontSize: 10, color: _textColor.withOpacity(0.4)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPickerDot(Color color) {
    return GestureDetector(
      onTap: () => setState(() => _selectedHighlightColor = color),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color.withOpacity(1.0),
          shape: BoxShape.circle,
          border: Border.all(
            color: _selectedHighlightColor.value == color.value ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }
}