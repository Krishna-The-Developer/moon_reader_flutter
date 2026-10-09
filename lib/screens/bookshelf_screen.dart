import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/book_model.dart';
import '../services/metadata_scanner.dart';
import '../widgets/shelf_book_item.dart';
import 'reader_screen.dart';

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";
  bool _spineMode = false;

  Future<void> _importBook() async {
    String? selectedPath;

    // 1. Pehle Linux native Zenity file picker try karega
    // 1. Android & Mobile Native File Picker + Permissions
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ["pdf", "epub", "cbz", "txt"],
        );
        if (result != null && result.files.isNotEmpty) {
          selectedPath = result.files.single.path;
        }
      } catch (e) {
        debugPrint("FilePicker error: $e");
      }
    } else {
      // 2. Desktop fallback (Linux)
      try {
        final result = await Process.run("zenity", [
          "--file-selection",
          "--title=Select E-Book (EPUB, CBZ, TXT, PDF)",
        ]);
        if (result.exitCode == 0) {
          final path = result.stdout.toString().trim();
          if (path.isNotEmpty && File(path).existsSync()) {
            selectedPath = path;
          }
        }
      } catch (_) {}

      if (selectedPath == null && mounted) {
        selectedPath = await _showInAppFilePicker(context);
      }
    }

    // 3. File select hone par book scan karke shelf me add karega
    if (selectedPath != null && mounted) {
      final file = File(selectedPath);
      final scannedBook = await MetadataScanner.scanAndCreateBook(file);
      final box = Hive.box<LocalBook>('bookshelf');
      await box.put(scannedBook.id, scannedBook);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${scannedBook.title}" to bookshelf!'),
          backgroundColor: Colors.green.shade800,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Built-in In-App Directory Browser (Zero external dependency)
  Future<String?> _showInAppFilePicker(BuildContext context) async {
    final home = Platform.environment['HOME'] ?? '/home';
    Directory currentDir = Directory(home);

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            List<FileSystemEntity> items = [];
            try {
              items = currentDir.listSync()
                ..sort((a, b) {
                  final aIsDir = a is Directory;
                  final bIsDir = b is Directory;
                  if (aIsDir && !bIsDir) return -1;
                  if (!aIsDir && bIsDir) return 1;
                  return a.path.toLowerCase().compareTo(b.path.toLowerCase());
                });
            } catch (_) {}

            return AlertDialog(
              backgroundColor: const Color(0xFF221811),
              title: Text(
                currentDir.path.split('/').last.isEmpty
                    ? '/'
                    : currentDir.path.split('/').last,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              content: SizedBox(
                width: 450,
                height: 400,
                child: Column(
                  children: [
                    if (currentDir.parent.path != currentDir.path)
                      ListTile(
                        leading:
                            const Icon(Icons.arrow_upward, color: Colors.amber),
                        title: const Text(".. (Go Up)",
                            style: TextStyle(color: Colors.white70)),
                        dense: true,
                        onTap: () {
                          setDialogState(() {
                            currentDir = currentDir.parent;
                          });
                        },
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          final isDir = item is Directory;
                          final name = item.uri.pathSegments
                              .where((s) => s.isNotEmpty)
                              .last;

                          if (!isDir) {
                            final ext = name.split('.').last.toLowerCase();
                            if (!['epub', 'cbz', 'txt', 'pdf'].contains(ext)) {
                              return const SizedBox.shrink();
                            }
                          }

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isDir ? Icons.folder : Icons.book,
                              color: isDir
                                  ? Colors.amber.shade700
                                  : Colors.lightGreenAccent,
                            ),
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: isDir ? Colors.white : Colors.white70),
                            ),
                            onTap: () {
                              if (isDir) {
                                setDialogState(() {
                                  currentDir = item;
                                });
                              } else {
                                Navigator.pop(ctx, item.path);
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text("Cancel",
                      style: TextStyle(color: Colors.white54)),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _showReadingModeSelector(LocalBook book) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.menu_book, color: Colors.amber),
                title: const Text("3D Realistic Page Curl"),
                subtitle: const Text("3D perspective curl with spine shadows"),
                onTap: () => _openReader(book, ReadingMode.curl3d),
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.lightBlue),
                title: const Text("Horizontal Swipe"),
                subtitle: const Text("Smooth page slide"),
                onTap: () => _openReader(book, ReadingMode.horizontal),
              ),
              ListTile(
                leading: const Icon(Icons.swap_vert, color: Colors.lightGreen),
                title: const Text("Continuous Vertical Scroll"),
                subtitle: const Text("Web scroll"),
                onTap: () => _openReader(book, ReadingMode.vertical),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openReader(LocalBook book, ReadingMode mode) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ReaderScreen(book: book, initialMode: mode)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<LocalBook>('bookshelf');

    return Scaffold(
      backgroundColor: const Color(0xFF19120C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF281C13),
        title: const Text('My Library',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_spineMode ? Icons.view_module : Icons.view_column),
            tooltip: 'Toggle Spine / Cover view',
            onPressed: () => setState(() => _spineMode = !_spineMode),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.amber),
            tooltip: 'Import Local Ebook',
            onPressed: _importBook,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) =>
                  setState(() => _searchQuery = v.trim().toLowerCase()),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText:
                    'Search title or author (books pull out from shelf)...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.amber),
                filled: true,
                fillColor: const Color(0xFF2B1E15),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: box.listenable(),
              builder: (context, Box<LocalBook> b, _) {
                final books = b.values.toList();
                if (books.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.shelves,
                            size: 70, color: Colors.white24),
                        const SizedBox(height: 12),
                        const Text("Your bookshelf is empty",
                            style: TextStyle(color: Colors.white54)),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _importBook,
                          icon: const Icon(Icons.file_open),
                          label: const Text("Import from Storage"),
                        ),
                      ],
                    ),
                  );
                }

                final int itemsPerRow = _spineMode ? 9 : 3;
                return ListView.builder(
                  padding: const EdgeInsets.only(top: 20, bottom: 40),
                  itemCount: (books.length / itemsPerRow).ceil(),
                  itemBuilder: (context, rowIndex) {
                    final start = rowIndex * itemsPerRow;
                    final end = (start + itemsPerRow < books.length)
                        ? start + itemsPerRow
                        : books.length;
                    final rowBooks = books.sublist(start, end);

                    return Column(
                      children: [
                        Container(
                          height: 165,
                          alignment: Alignment.bottomLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: rowBooks.map((book) {
                              final isMatch = _searchQuery.isNotEmpty &&
                                  (book.title
                                          .toLowerCase()
                                          .contains(_searchQuery) ||
                                      book.author
                                          .toLowerCase()
                                          .contains(_searchQuery));
                              return ShelfBookItem(
                                book: book,
                                isHighlighted: isMatch,
                                showSpineOnly: _spineMode,
                                onTap: () => _showReadingModeSelector(book),
                              );
                            }).toList(),
                          ),
                        ),
                        // Wooden Shelf Plank
                        Container(
                          height: 18,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6D4C41), Color(0xFF3E2723)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black87,
                                  blurRadius: 10,
                                  offset: Offset(0, 8))
                            ],
                          ),
                        ),
                        const SizedBox(height: 35),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
