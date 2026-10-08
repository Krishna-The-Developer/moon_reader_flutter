import 'package:hive/hive.dart';

class LocalBook extends HiveObject {
  final String id;
  String title;
  final String filePath;
  final String format; // 'pdf', 'epub', 'cbz', 'txt'
  int lastPage;
  int totalPages;
  DateTime lastRead;
  String? coverPath;
  String author;
  List<int> bookmarkedPages;
  List<String> highlights; // Format: "pageIndex|colorValue|text"

  LocalBook({
    required this.id,
    required this.title,
    required this.filePath,
    required this.format,
    this.lastPage = 0,
    this.totalPages = 1,
    DateTime? lastRead,
    this.coverPath,
    this.author = "Unknown Author",
    List<int>? bookmarkedPages,
    List<String>? highlights,
  })  : lastRead = lastRead ?? DateTime.now(),
        bookmarkedPages = bookmarkedPages ?? [],
        highlights = highlights ?? [];

  void safeSave() {
    if (isInBox) {
      save();
    }
  }
}

// Built-in Adapter
class LocalBookAdapter extends TypeAdapter<LocalBook> {
  @override
  final int typeId = 0;

  @override
  LocalBook read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalBook(
      id: fields[0] as String,
      title: fields[1] as String,
      filePath: fields[2] as String,
      format: fields[3] as String,
      lastPage: fields[4] as int? ?? 0,
      totalPages: fields[5] as int? ?? 1,
      lastRead: fields[6] as DateTime?,
      coverPath: fields[7] as String?,
      author: fields[8] as String? ?? "Unknown Author",
      bookmarkedPages: (fields[9] as List?)?.cast<int>(),
      highlights: (fields[10] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, LocalBook obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.filePath)
      ..writeByte(3)
      ..write(obj.format)
      ..writeByte(4)
      ..write(obj.lastPage)
      ..writeByte(5)
      ..write(obj.totalPages)
      ..writeByte(6)
      ..write(obj.lastRead)
      ..writeByte(7)
      ..write(obj.coverPath)
      ..writeByte(8)
      ..write(obj.author)
      ..writeByte(9)
      ..write(obj.bookmarkedPages)
      ..writeByte(10)
      ..write(obj.highlights);
  }
}