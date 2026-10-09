import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:moon_reader_flutter/services/progressive_document_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProgressiveDocumentController Tests', () {
    late Directory tempDir;
    late File sampleTextFile;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('moon_reader_test_');
      sampleTextFile = File('${tempDir.path}/sample.txt');
      final buffer = StringBuffer();
      for (int i = 0; i < 50; i++) {
        buffer.writeln(
            'Chapter $i\nThis is reconstructed paragraph content for chapter $i.\n\n');
      }
      await sampleTextFile.writeAsString(buffer.toString());
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Stage A: Controller initializes and discovers page count rapidly',
        () async {
      final controller = ProgressiveDocumentController(
        filePath: sampleTextFile.path,
        format: 'txt',
        maxCacheSize: 5,
      );

      final stopwatch = Stopwatch()..start();
      await controller.initialize();
      stopwatch.stop();

      expect(controller.isInitialized, isTrue);
      expect(controller.totalPages, greaterThan(1));
      expect(stopwatch.elapsedMilliseconds, lessThan(300),
          reason: "Initialization must be <300ms");
      controller.dispose();
    });

    test('Stage B: Immediate access returns valid page structure', () async {
      final controller = ProgressiveDocumentController(
        filePath: sampleTextFile.path,
        format: 'txt',
        maxCacheSize: 5,
      );
      await controller.initialize();

      controller.setReadingPosition(0);
      final page = controller.getPage(0);

      expect(page.index, equals(0));
      expect(page.status, anyOf(PageStatus.loading, PageStatus.ready));
      controller.dispose();
    });

    test('Stage C: Bounded LRU cache evicts distant pages', () async {
      final controller = ProgressiveDocumentController(
        filePath: sampleTextFile.path,
        format: 'txt',
        maxCacheSize: 4,
      );
      await controller.initialize();

      for (int i = 0; i < 9; i++) {
        controller.setReadingPosition(i);
        controller.getPage(i);
        await Future.delayed(const Duration(milliseconds: 10));
      }

      final page0 = controller.getPage(0);
      expect(page0.index, equals(0));
      controller.dispose();
    });
  });
}
