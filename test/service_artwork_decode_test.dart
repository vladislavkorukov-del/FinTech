import 'dart:async';
import 'dart:ui' as ui;
import 'package:finora/domain/service_catalog.dart';
import 'package:finora/presentation/widgets/service_logo_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ImageInfo> _frame(ImageProvider provider) {
  final ready = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      ready.complete(info.clone());
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stack) {
      ready.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return ready.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'every shipped service decodes into artwork visible against its own plate',
    () async {
      for (final service in ServiceCatalog.entries) {
        final asset = service.assetPath!;
        final ImageProvider provider = asset.endsWith('.svg')
            ? ServiceSvgImage(asset, pixels: 128)
            : ResizeImage(
                AssetImage(asset),
                width: 128,
                height: 128,
                policy: ResizeImagePolicy.fit,
              );
        final info = await _frame(provider);
        try {
          final data = (await info.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          var visible = 0;
          for (var i = 0; i < data.length; i += 4) {
            if (data[i + 3] < 128) continue;
            final color = service.preserveColors ? null : service.color;
            final r = color == null ? data[i] : (color >> 16) & 255;
            final g = color == null ? data[i + 1] : (color >> 8) & 255;
            final b = color == null ? data[i + 2] : color & 255;
            if ((r - ((service.background >> 16) & 255)).abs() +
                    (g - ((service.background >> 8) & 255)).abs() +
                    (b - (service.background & 255)).abs() >
                45) {
              visible++;
            }
          }
          expect(
            visible,
            greaterThan(15),
            reason: '${service.id}: empty or invisible artwork',
          );
        } finally {
          info.dispose();
          await provider.evict();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
