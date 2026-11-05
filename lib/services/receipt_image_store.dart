import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';

/// Keep source images unchanged in private storage. Never delete a user's file.
class ReceiptImageStore {
  static const maxBytes = 20 * 1024 * 1024;

  Future<String?> pick(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      requestFullMetadata: false,
    );
    return image == null ? null : copy(image);
  }

  Future<String> copy(XFile source) async {
    if (await source.length() > maxBytes) {
      throw const FormatException('Изображение превышает 20 МБ.');
    }
    final bytes = await source.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Выберите изображение размером до 20 МБ.');
    }
    final String extension;
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      extension = 'png';
    } else if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      extension = 'jpg';
    } else if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      extension = 'webp';
    } else {
      throw const FormatException(
        'Для распознавания выберите PNG, JPEG или WebP.',
      );
    }
    final root = await getApplicationSupportDirectory();
    final folder = await Directory(
      p.join(root.path, 'receipts'),
    ).create(recursive: true);
    final file = File(
      p.join(folder.path, 'scan-${const Uuid().v4()}.$extension'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> discardIfUnused(String path, FinanceData data) async {
    if (data.entries.any((e) => e.attachmentPath == path) ||
        !p.basename(path).startsWith('scan-')) {
      return;
    }
    try {
      final root = await getApplicationSupportDirectory();
      final folder = await Directory(
        p.join(root.path, 'receipts'),
      ).resolveSymbolicLinks();
      final file = File(path);
      final canonical = await file.resolveSymbolicLinks();
      if (p.isWithin(folder, canonical)) await file.delete();
    } on FileSystemException {
      // A canceled scan may already have been cleaned up.
    }
  }

  Future<void> discardConsumedShare(String path) async {
    try {
      final root = await getTemporaryDirectory();
      final folder = await Directory(
        p.join(root.path, 'receipt_shares'),
      ).resolveSymbolicLinks();
      final file = File(path);
      if (p.isWithin(folder, await file.resolveSymbolicLinks())) {
        await file.delete();
      }
    } on FileSystemException {
      // Never delete a source outside the app-owned share cache.
    }
  }
}
