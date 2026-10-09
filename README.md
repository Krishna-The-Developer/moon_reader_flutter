# AK reader 📖

An advanced, high-performance Flutter document reader designed for authentic physical-book reading aesthetics with dynamic 3D page curl physics, progressive document loading, and OCR page scanning.

## ✨ Key Features

- **Realistic 3D Page Curl:** Touch-point dynamic fold geometry (60 FPS) with rigid hardcover spine rotation and soft-paper physics.
- **Warm Cream Paper Aesthetic:** High-contrast book ink typography on authentic warm paper tones (`#F5EACB`).
- **Progressive Document Loading:** Immediate first-page render (<60ms) with a bounded 25-page LRU cache to eliminate OOM crashes on large files.
- **Universal Multi-Format Support:** Robust parsing for PDF, EPUB (with chapter tree & raw ZIP fallback), CBZ/CBR comics, and TXT.
- **Book Page OCR Scanner:** Physical page capture via Camera/Gallery using Google ML Kit with heading and layout reconstruction.
- **Scoped Storage Compliant:** Native Android 11+ Storage Access Framework (SAF) integration.

## 🛠️ Tech Stack

- **Framework:** Flutter & Dart
- **Storage & Cache:** Hive
- **Engines:** `pdfx`, `epubx`, `archive`, `google_mlkit_text_recognition`, `image_picker`

## 🚀 Getting Started

```bash
flutter pub get
flutter test
flutter run
```
