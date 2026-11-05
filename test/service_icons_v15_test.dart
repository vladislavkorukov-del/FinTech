import 'dart:io';
import 'dart:ui' as ui;

import 'package:finora/domain/service_catalog.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/service_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _waitForLogo(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final frames = tester.widgetList<RawImage>(find.byType(RawImage));
    if (frames.isNotEmpty && frames.every((f) => f.image != null)) return;
  }
}

void main() {
  testWidgets(
    'every catalog service renders actual local PNG artwork on light and dark surfaces',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final service in ServiceCatalog.entries) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(brightness, 'coffee'),
              home: Scaffold(
                body: ServiceBadge(serviceId: service.id, size: 38),
              ),
            ),
          );
          final image = tester.widget<Image>(find.byType(Image));
          final provider = image.image as ResizeImage;
          expect(
            (provider.imageProvider as AssetImage).assetName,
            service.renderAssetPath,
          );
          expect(service.renderAssetPath, endsWith('/${service.id}.png'));
          await tester.runAsync(
            () => precacheImage(
              provider,
              tester.element(find.byType(ServiceBadge)),
            ),
          );
          await tester.pump();
          final frame = tester.widget<RawImage>(find.byType(RawImage)).image;
          expect(frame, isNotNull, reason: '${service.id}/$brightness');
          final rgba = await tester.runAsync(
            () => frame!.toByteData(format: ui.ImageByteFormat.rawRgba),
          );
          final data = rgba!.buffer.asUint8List();
          var visible = 0;
          for (var i = 0; i < data.length; i += 4) {
            if (data[i + 3] == 0) continue;
            if (data[i + 3] < 128) continue;
            final color = image.color?.toARGB32();
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
            greaterThan(5),
            reason: '${service.id}: invisible against brand plate',
          );
          expect(
            find.byIcon(Icons.subscriptions_outlined),
            findsNothing,
            reason: service.id,
          );
          expect(image.filterQuality, FilterQuality.high);
          expect(tester.takeException(), isNull, reason: service.id);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'rapid catalog changes survive image-cache eviction and return to earlier service',
    (tester) async {
      for (final service in ServiceCatalog.entries.take(60)) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ServiceBadge(serviceId: service.id)),
          ),
        );
        PaintingBinding.instance.imageCache.clear();
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ServiceBadge(serviceId: 'spotify')),
        ),
      );
      await _waitForLogo(tester);
      final provider =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      expect(
        (provider.imageProvider as AssetImage).assetName,
        'assets/services/raster/spotify.png',
      );
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(find.byIcon(Icons.subscriptions_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing custom upload falls back to its actual catalog logo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark, 'coffee'),
        home: const Scaffold(
          body: ServiceBadge(
            serviceId: 'spotify',
            customIconPath: '/missing/private/service_icons/old.png',
          ),
        ),
      ),
    );
    await _waitForLogo(tester);
    expect(find.byIcon(Icons.subscriptions_outlined), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'corrupt custom upload falls back to the correct brand instead of generic glyph',
    (tester) async {
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('finance-icon-test-'),
      );
      final file = File('${dir!.path}/broken.png');
      await tester.runAsync(() => file.writeAsBytes([1, 2, 3, 4]));
      addTearDown(() => dir.delete(recursive: true));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServiceBadge(serviceId: 'netflix', customIconPath: file.path),
          ),
        ),
      );
      await _waitForLogo(tester);
      expect(find.byIcon(Icons.subscriptions_outlined), findsNothing);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}
