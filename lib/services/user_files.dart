import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Files the app keeps for the person's data: receipt and screenshot images
/// (`receipts/`), uploaded service icons (`service_icons/`) and dream photos
/// (`goal_photos/`, 1.55). Removed when all data is reset (1.18); nothing
/// outside these app folders is touched.
abstract final class UserFiles {
  static const folders = ['receipts', 'service_icons', 'goal_photos'];

  static Future<void> wipe() async {
    final root = await getApplicationSupportDirectory();
    for (final name in folders) {
      final folder = Directory(p.join(root.path, name));
      if (await folder.exists()) await folder.delete(recursive: true);
    }
  }
}
