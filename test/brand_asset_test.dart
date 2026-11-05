import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/finance_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const approvedDigest =
      '1520aa31c87f3b5ee37aeed64432be9c8ca4c17bd3fd547329916906799e2388';

  test(
    'header cutout has transparent corners and no opaque background plate',
    () async {
      final bytes = await rootBundle.load(FinanceBrand.asset);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final rgba = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final pixels = rgba.buffer.asUint8List();
      final width = frame.image.width;
      final height = frame.image.height;
      expect(pixels[3], 0);
      expect(pixels[(width - 1) * 4 + 3], 0);
      expect(pixels[(height - 1) * width * 4 + 3], 0);
      var clear = 0;
      var visible = 0;
      for (var i = 3; i < pixels.length; i += 4) {
        if (pixels[i] == 0) clear++;
        if (pixels[i] > 200) visible++;
      }
      expect(clear / (width * height), greaterThan(.7));
      expect(visible / (width * height), greaterThan(.1));
      frame.image.dispose();
      codec.dispose();
    },
  );

  testWidgets('header animates and honors reduced motion and hidden routes', (
    tester,
  ) async {
    Widget app({bool reduce = false, bool enabled = true}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: TickerMode(
          enabled: enabled,
          child: const SizedBox(width: 54, height: 54, child: FinanceBrand()),
        ),
      ),
    );
    double offset() => tester
        .widget<Transform>(find.byKey(const ValueKey('finance-logo-motion')))
        .transform
        .storage[13];
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 550));
    expect(offset().abs(), greaterThan(1));
    await tester.pumpWidget(app(reduce: true));
    expect(offset(), 0);
    await tester.pump(const Duration(seconds: 7));
    expect(offset(), 0);
    await tester.pumpWidget(app(enabled: false));
    await tester.pump(const Duration(milliseconds: 550));
    expect(offset(), 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  test(
    'Flutter and Android use the exact approved PNG from the supplied ZIP',
    () async {
      final bundled = await rootBundle.load(FinanceBrand.originalAsset);
      expect(
        sha256.convert(bundled.buffer.asUint8List()).toString(),
        approvedDigest,
      );
      final native = await File(
        'android/app/src/main/res/drawable-nodpi/finance_brand.png',
      ).readAsBytes();
      expect(sha256.convert(native).toString(), approvedDigest);
      final launcher = await File(
        'android/app/src/main/res/drawable/ic_launcher.xml',
      ).readAsString();
      expect(launcher, contains('@drawable/finance_brand'));
      expect(launcher, isNot(contains('<vector')));
    },
  );

  testWidgets(
    'approved logo decodes and stays at screen center in both themes',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final width in [320.0, 412.0]) {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(brightness, 'coffee'),
              home: const Scaffold(
                body: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: FinanceHeader(),
                  ),
                ),
              ),
            ),
          );
          final context = tester.element(find.byType(FinanceBrand));
          await tester.runAsync(
            () => precacheImage(const AssetImage(FinanceBrand.asset), context),
          );
          await tester.pumpAndSettle();
          final image = tester.widget<RawImage>(
            find.descendant(
              of: find.byType(FinanceBrand),
              matching: find.byType(RawImage),
            ),
          );
          expect(image.image, isNotNull);
          expect(image.image!.width, 1254);
          expect(image.image!.height, 1254);
          expect(
            tester
                .getCenter(find.byKey(const ValueKey('finance-brand-center')))
                .dx,
            closeTo(width / 2, .01),
          );
          expect(
            tester.getSize(find.byKey(const ValueKey('finance-brand-center'))),
            const Size(54, 54),
          );
          expect(tester.takeException(), isNull);
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
