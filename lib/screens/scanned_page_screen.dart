import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/book_model.dart';
import '../models/scanned_page.dart';

class ScannedPageScreen extends StatefulWidget {
  final ScannedPageData initialData;

  const ScannedPageScreen({super.key, required this.initialData});

  @override
  State<ScannedPageScreen> createState() => _ScannedPageScreenState();
}

class _ScannedPageScreenState extends State<ScannedPageScreen> {
  late ScannedPageData _pageData;
  bool _showOriginalPreview = false;

  final List<Color> _paperPresets = const [
    Color(0xFFF5EACB), // Warm Cream (Default book tone)
    Color(0xFFF3E5C5), // Classic Vintage Amber
    Color(0xFFFAF6EE), // Natural Off-White
    Color(0xFFEFE6D5), // Aged Parchment
  ];

  @override
  void initState() {
    super.initState();
    _pageData = widget.initialData;
  }

  void _editBlock(int index) {
    final controller =
        TextEditingController(text: _pageData.blocks[index].text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2C1E14),
        title:
            const Text('Edit OCR Text', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 8,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Correct recognized words...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A373)),
            onPressed: () {
              setState(() {
                _pageData.blocks[index].text = controller.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Apply Changes',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveToLibrary() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final title = _pageData.blocks.isNotEmpty
          ? _pageData.blocks.first.text.split("\n").first
          : "Scanned Page";
      final cleanTitle = title.length > 28 ? title.substring(0, 28) : title;

      final fileName = "Scan_${DateTime.now().millisecondsSinceEpoch}.txt";
      final file = File("${docDir.path}/$fileName");
      await file.writeAsString(_pageData.fullText);

      final box = Hive.box<LocalBook>("bookshelf");
      final newBook = LocalBook(
        id: file.path,
        title: cleanTitle.replaceAll("\n", " ").trim(),
        filePath: file.path,
        format: "txt",
        author: "Scanned Document",
        lastPage: 0,
        totalPages: 1,
        lastRead: DateTime.now(),
        bookmarkedPages: [],
        highlights: [],
      );

      await box.put(newBook.id, newBook);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Saved \"$cleanTitle\" to My Library!"),
          backgroundColor: const Color(0xFF5A381E),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error saving page: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B120C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A170C),
        elevation: 0,
        title: const Text('Scanned Book Page',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          IconButton(
            tooltip: _showOriginalPreview
                ? 'View Reconstructed'
                : 'View Original Photo',
            icon: Icon(
              _showOriginalPreview ? Icons.menu_book : Icons.photo_library,
              color: const Color(0xFFD4A373),
            ),
            onPressed: () =>
                setState(() => _showOriginalPreview = !_showOriginalPreview),
          ),
          IconButton(
            tooltip: 'Style Settings',
            icon: const Icon(Icons.tune, color: Colors.white70),
            onPressed: _showSettingsSheet,
          ),
          IconButton(
            tooltip: 'Save to Shelf',
            icon: const Icon(Icons.bookmark_add, color: Color(0xFFD4A373)),
            onPressed: _saveToLibrary,
          ),
        ],
      ),
      body: SafeArea(
        child: _showOriginalPreview
            ? _buildOriginalImage()
            : _buildReconstructedPaper(),
      ),
    );
  }

  Widget _buildOriginalImage() {
    return Center(
      child: InteractiveViewer(
        child: Image.file(
          File(_pageData.imagePath),
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildReconstructedPaper() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _pageData.paperColor,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              offset: Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Spine gutter shadow on left edge
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 18,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0x28000000), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            // Reconstructed Content
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < _pageData.blocks.length; i++)
                    _buildBlockItem(i, _pageData.blocks[i]),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockItem(int index, ScannedBlock block) {
    TextStyle style;
    switch (block.type) {
      case ScannedBlockType.heading:
        style = TextStyle(
          fontFamily: 'serif',
          fontSize: _pageData.fontSize * 1.45,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF221A12),
          height: 1.35,
        );
        break;
      case ScannedBlockType.subheading:
        style = TextStyle(
          fontFamily: 'serif',
          fontSize: _pageData.fontSize * 1.2,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF2A2016),
          height: 1.45,
        );
        break;
      case ScannedBlockType.paragraph:
        style = TextStyle(
          fontFamily: 'serif',
          fontSize: _pageData.fontSize,
          height: _pageData.lineSpacing,
          color: const Color(0xFF2B221B),
          letterSpacing: 0.15,
        );
        break;
    }

    return Padding(
      padding: EdgeInsets.only(top: block.relativeTopGap),
      child: InkWell(
        onLongPress: () => _editBlock(index),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: Text(
            block.text,
            textAlign: block.alignment,
            style: style,
          ),
        ),
      ),
    );
  }

  void _showSettingsSheet() {
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
                const Text('Paper Color',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final color in _paperPresets)
                      GestureDetector(
                        onTap: () {
                          setState(() => _pageData.paperColor = color);
                          setModalState(() {});
                        },
                        child: Container(
                          width: 38,
                          height: 38,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _pageData.paperColor == color
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
                const Text(
                    'Font Size: \${_pageData.fontSize.toStringAsFixed(1)}',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                Slider(
                  value: _pageData.fontSize,
                  min: 12.0,
                  max: 26.0,
                  activeColor: const Color(0xFFD4A373),
                  onChanged: (val) {
                    setState(() => _pageData.fontSize = val);
                    setModalState(() {});
                  },
                ),
                const Text(
                    'Line Spacing: \${_pageData.lineSpacing.toStringAsFixed(1)}',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                Slider(
                  value: _pageData.lineSpacing,
                  min: 1.3,
                  max: 2.4,
                  activeColor: const Color(0xFFD4A373),
                  onChanged: (val) {
                    setState(() => _pageData.lineSpacing = val);
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
