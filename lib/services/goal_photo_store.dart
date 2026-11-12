import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 1.55: dream photos, already cropped to the card, kept as private files in
/// the app's `goal_photos` folder (removed with all data on reset; carried
/// in the JSON backup). Never touches the person's own gallery files.
class GoalPhotoStore {
  const GoalPhotoStore({this.root});

  /// Folder that holds `goal_photos`; the app support folder by default.
  final Directory? root;

  static const folder = 'goal_photos';
  static const maxSourceBytes = 25 * 1024 * 1024;

  /// The bytes of a photo picked from the gallery, or null when cancelled.
  Future<Uint8List?> pickSource() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (image == null) return null;
    if (await image.length() > maxSourceBytes) {
      throw const FormatException('Фото больше 25 МБ. Выберите другое.');
    }
    return image.readAsBytes();
  }

  Future<Directory> _folder() async {
    final base = root ?? await getApplicationSupportDirectory();
    return Directory(p.join(base.path, folder)).create(recursive: true);
  }

  /// Saves a cropped PNG and returns its path.
  Future<String> save(Uint8List png) async {
    if (png.isEmpty) throw const FormatException('Пустое изображение.');
    final file = File(
      p.join((await _folder()).path, 'dream-${const Uuid().v4()}.png'),
    );
    await file.writeAsBytes(png, flush: true);
    return file.path;
  }

  /// Removes a photo this store saved; any other path is left alone.
  Future<void> delete(String? path) async {
    if (path == null) return;
    final folder = await _folder();
    final file = File(path);
    if (p.isWithin(folder.path, file.path) && await file.exists()) {
      await file.delete();
    }
  }
}
