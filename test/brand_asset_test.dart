import 'dart:io';

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
    'Flutter and Android use the exact approved PNG from the supplied ZIP',
    () async {
      final bundled = await rootBundle.load(FinanceBrand.asset);
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
