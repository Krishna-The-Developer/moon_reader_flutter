// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

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
      lastPage: fields[4] as int,
      totalPages: fields[5] as int,
      lastRead: fields[6] as DateTime?,
      coverPath: fields[7] as String?,
      author: fields[8] as String,
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

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalBookAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
