import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/book_model.dart';
import 'screens/bookshelf_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Local Hive Database initialize
  await Hive.initFlutter();
  
  // 2. Custom Book Model Adapter register
  Hive.registerAdapter(LocalBookAdapter());
  
  // 3. Bookshelf Box open
  await Hive.openBox<LocalBook>('bookshelf');

  runApp(const MoonReaderApp());
}

class MoonReaderApp extends StatelessWidget {
  const MoonReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moon Reader Kali',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF140D07),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF281C13),
          elevation: 0,
        ),
      ),
      home: const BookshelfScreen(),
    );
  }
}