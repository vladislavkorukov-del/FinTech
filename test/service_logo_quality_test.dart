import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/service_badge.dart';
import 'package:finora/presentation/widgets/service_logo_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _SvgBundle extends CachingAssetBundle {
  _SvgBundle(this.source);
  final String source;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(source)));
}

class _DelayedSvgBundle extends CachingAssetBundle {
  final ready = Completer<ByteData>();
  @override
  Future<ByteData> load(String key) => ready.future;
}

Future<ImageInfo> _decode(ImageProvider provider) {
  final ready = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) {
      ready.complete(image.clone());
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
    'failed logo render is evicted instead of retaining a failed pending frame',
    () async {
      const provider = ServiceSvgImage(
        'assets/services/spotify.svg',
        pixels: 1,
      );
      final key = await provider.obtainKey(ImageConfiguration.empty);
      await expectLater(_decode(provider), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(
        PaintingBinding.instance.imageCache.statusForKey(key).untracked,
        isTrue,
      );
    },
  );

  testWidgets(
    'pending raster survives cache eviction without a late disposed-stream failure',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final bundle = _DelayedSvgBundle();
      final provider = ServiceSvgImage(
        'delayed.svg',
        pixels: 64,
        bundle: bundle,
      );
      final key = await provider.obtainKey(ImageConfiguration.empty);
      final stream = provider.resolve(ImageConfiguration.empty);
      final initial = ImageStreamListener((_, _) {});
      stream.addListener(initial);
      expect(PaintingBinding.instance.imageCache.evict(key), isTrue);
      stream.removeListener(initial);
      await tester.pump();
      expect(stream.completer!.hasListeners, isFalse);
      final probe = stream.completer!.keepAlive();
      probe.dispose();
      final ready = Completer<ImageInfo>();
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        ready.complete(info.clone());
        stream.removeListener(listener);
      });
      stream.addListener(listener);
      bundle.ready.complete(
        ByteData.sublistView(
          Uint8List.fromList(
            utf8.encode(
              '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><circle cx="10" cy="10" r="8" fill="#00ff00"/></svg>',
            ),
          ),
        ),
      );
      final decoded = await tester.runAsync(() => ready.future);
      expect(decoded!.image.width, 64);
      decoded.dispose();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(stream.completer!.hasListeners, isFalse);
      final cacheState = PaintingBinding.instance.imageCache.statusForKey(key);
      expect(cacheState.untracked, isTrue);
      final remaining = stream.completer!.keepAlive();
      remaining.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'provider honors inherited asset bundles without a hardcoded root bundle',
    (tester) async {
      final bundle = _SvgBundle(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><circle cx="10" cy="10" r="8" fill="#00ff00"/></svg>',
      );
      const provider = ServiceSvgImage('inherited.svg', pixels: 64);
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: bundle,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: Image(image: provider),
          ),
        ),
      );
      final context = tester.element(find.byType(Image));
      await tester.runAsync(() => precacheImage(provider, context));
      await tester.pumpAndSettle();
      expect(tester.widget<RawImage>(find.byType(RawImage)).image!.width, 64);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'genuine curved logo has transparent margins and antialiased edge pixels',
    () async {
      final frame = await _decode(
        const ServiceSvgImage('assets/services/spotify.svg', pixels: 128),
      );
      try {
        expect(frame.image.width, 128);
        expect(frame.image.height, 128);
        final bytes = (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final alpha = [for (var i = 3; i < bytes.length; i += 4) bytes[i]];
        expect(alpha.first, 0);
        expect(alpha.where((a) => a > 0 && a < 255).length, greaterThan(150));
        expect(alpha.where((a) => a == 255).length, greaterThan(2000));
      } finally {
        frame.dispose();
      }
    },
  );

  test(
    'wide multicolor SVG keeps proportions, original colors and transparent letterbox',
    () async {
      final bundle = _SvgBundle(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 80 20"><path fill="#ff0000" d="M0 0h40v20H0z"/><path fill="#0000ff" d="M40 0h40v20H40z"/></svg>',
      );
      final frame = await _decode(
        ServiceSvgImage('wide.svg', pixels: 128, bundle: bundle),
      );
      try {
        final bytes = (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        List<int> at(int x, int y) =>
            bytes.sublist((y * 128 + x) * 4, (y * 128 + x) * 4 + 4);
        expect(at(32, 64), [255, 0, 0, 255]);
        expect(at(96, 64), [0, 0, 255, 255]);
        expect(at(64, 32)[3], 0);
        expect(at(64, 96)[3], 0);
      } finally {
        frame.dispose();
      }
    },
  );

  testWidgets(
    'badge changes resolution with display density and smooths outer clipping',
    (tester) async {
      for (final dpr in [1.25, 3.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(Brightness.dark, 'coffee'),
            home: MediaQuery(
              data: MediaQueryData(devicePixelRatio: dpr),
              child: const Scaffold(
                body: ServiceBadge(serviceId: 'spotify', size: 44.5),
              ),
            ),
          ),
        );
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.image, isA<ServiceSvgImage>());
        final provider = image.image as ServiceSvgImage;
        expect(
          provider.pixels,
          greaterThanOrEqualTo((44.5 * .64 * dpr * 2).ceil()),
        );
        expect(image.filterQuality, FilterQuality.high);
        expect(image.isAntiAlias, isTrue);
        final plate = tester.widget<Container>(
          find.byKey(const ValueKey('service-badge-spotify')),
        );
        expect(plate.clipBehavior, Clip.antiAlias);
        await tester.runAsync(
          () => precacheImage(
            provider,
            tester.element(find.byType(ServiceBadge)),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<RawImage>(find.byType(RawImage)).image!.width,
          provider.pixels,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
