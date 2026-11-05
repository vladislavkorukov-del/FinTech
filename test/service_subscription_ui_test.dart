import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/service_catalog.dart';
import 'package:finora/presentation/controller.dart';
import 'package:finora/presentation/screens/management.dart';
import 'package:finora/presentation/theme/app_theme.dart';
import 'package:finora/presentation/widgets/service_badge.dart';
import 'package:finora/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Notifications extends NotificationService {
  bool permissionAllowed = true;
  int permissionRequests = 0;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionAllowed;
  }

  @override
  Future<void> sync(FinanceData data) async {}
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late FinanceRepository repository;
  late FinanceController controller;
  late _Notifications notifications;
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAFUlEQVR4nGMUCVj1nwEJMDGgAcICAIYaAhXIS0xyAAAAAElFTkSuQmCC',
  );
  const imagePicker = MethodChannel('plugins.flutter.io/image_picker');
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    await initializeDateFormatting('ru');
    directory = await Directory.systemTemp.createTemp('finora-services-');
    repository = await FinanceRepository.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/ledger.db',
    );
    await repository.save(
      const FinanceData(
        accounts: [Account(id: 'card', name: 'Карта', openingMinor: 1000000)],
        categories: [
          Category(
            id: 'subscriptions',
            name: 'Подписки',
            kind: EntryKind.expense,
          ),
          Category(
            id: 'archived',
            name: 'Старая категория',
            kind: EntryKind.expense,
            archived: true,
          ),
          Category(id: 'salary', name: 'Зарплата', kind: EntryKind.income),
        ],
        members: [Member(id: 'me', name: 'Я')],
      ),
    );
    notifications = _Notifications();
    controller = FinanceController(
      repository,
      notifications,
      await repository.load(),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (
      call,
    ) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return directory.path;
      }
      throw MissingPluginException();
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(imagePicker, (
      call,
    ) async {
      if (call.method == 'pickImage') return '${directory.path}/source.png';
      throw MissingPluginException();
    });
    await File('${directory.path}/source.png').writeAsBytes(image);
  });
  tearDown(() async {
    controller.dispose();
    await repository.close();
    await directory.delete(recursive: true);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(imagePicker, null);
  });

  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    double scale = 1,
    Size size = const Size(400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FinanceScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, 'lime'),
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              alwaysUse24HourFormat: true,
            ),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder sheetScroll() => find
      .descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      )
      .first;
  Future<void> reveal(WidgetTester tester, Finder item) async {
    await tester.scrollUntilVisible(item, 220, scrollable: sheetScroll());
    await tester.pumpAndSettle();
  }

  Future<void> flushUntil(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 80 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(ready(), isTrue);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, bool Function() ready) async {
    await reveal(tester, find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await flushUntil(tester, ready);
  }

  Future<void> newSubscription(WidgetTester tester) async {
    await mount(
      tester,
      const RecurringScreen(initialPaymentType: 'subscription'),
    );
    await tester.tap(find.byTooltip('Добавить подписку'));
    await tester.pumpAndSettle();
  }

  test(
    'catalog RU/EN search is case insensitive and every real logo has a verified source',
    () async {
      expect(ServiceCatalog.entries.length, greaterThanOrEqualTo(40));
      expect(ServiceCatalog.search('СПОТИФАЙ').single.id, 'spotify');
      expect(ServiceCatalog.search('sPoTiFy').single.id, 'spotify');
      expect(ServiceCatalog.search('ЯНДЕКС ПЛЮС').single.id, 'yandex_plus');
      expect(
        ServiceCatalog.search('ЮТУБ').map((s) => s.id),
        containsAll(['youtube_premium', 'youtube_music']),
      );
      expect(ServiceCatalog.search('СЕРФШАРК').single.id, 'surfshark');
      expect(ServiceCatalog.byId('okko')!.assetPath, isNull);
      expect(ServiceCatalog.byName('NETFLIX')!.id, 'netflix');
      expect(ServiceCatalog.byName('Спотифай')!.id, 'spotify');
      expect(ServiceCatalog.byName('Netflix Family'), isNull);
      expect(ServiceCatalog.byName('Музыка'), isNull);
      expect(ServiceCatalog.byName('облако'), isNull);
      final manifest =
          jsonDecode(
                await rootBundle.loadString('assets/services/manifest.json'),
              )
              as Map<String, dynamic>;
      var logos = 0;
      for (final item in manifest['items'] as List<dynamic>) {
        final row = item as Map<String, dynamic>;
        if (row['assetPath'] == null) continue;
        final asset = await rootBundle.load(row['assetPath'] as String);
        final bytes = asset.buffer.asUint8List(
          asset.offsetInBytes,
          asset.lengthInBytes,
        );
        expect(
          sha256.convert(bytes).toString(),
          row['sha256'],
          reason: row['id'] as String,
        );
        expect(utf8.decode(bytes), startsWith('<svg'));
        expect(row['svgUrl'], contains(manifest['sourceCommit']));
        logos++;
      }
      expect(logos, greaterThanOrEqualTo(40));
    },
  );

  test(
    'custom icon importer preserves original bytes and rejects oversized or nonimage files',
    () async {
      final original = File('${directory.path}/source.png');
      final copy = await ServiceIconStore.importImage(
        XFile(original.path),
        directory: directory,
      );
      expect(copy, contains('/service_icons/'));
      expect(copy, isNot(original.path));
      expect(await File(copy).readAsBytes(), image);
      expect(await original.readAsBytes(), image);
      await expectLater(
        ServiceIconStore.importImage(
          XFile.fromData(Uint8List(ServiceIconStore.maxBytes + 1)),
          directory: directory,
        ),
        throwsFormatException,
      );
      await expectLater(
        ServiceIconStore.importImage(
          XFile.fromData(Uint8List.fromList(utf8.encode('<svg>fake</svg>'))),
          directory: directory,
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'Russian service search selects genuine Spotify logo and persists chosen service',
    (tester) async {
      await newSubscription(tester);
      await tester.tap(
        find.byKey(const ValueKey('choose-subscription-service')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('service-search')),
        'СПОТИФАЙ',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('service-option-spotify')),
        findsOneWidget,
      );
      expect(find.byType(SvgPicture), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('service-option-spotify')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Spotify',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '399');
      await save(tester, () => controller.data.recurring.length == 1);
      final rule = controller.data.recurring.single;
      expect(rule.serviceId, 'spotify');
      expect(rule.name, 'Spotify');
      expect(rule.paymentType, 'subscription');
      expect(rule.amountMinor, 39900);
      expect(rule.reminderEnabled, isFalse);
      expect(rule.automatic, isFalse);
      expect(notifications.permissionRequests, 0);
      final stored = await tester.runAsync(repository.load);
      expect(stored!.recurring.single.serviceId, 'spotify');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom service image is copied to managed storage, saved and portable',
    (tester) async {
      await newSubscription(tester);
      await tester.tap(
        find.byKey(const ValueKey('choose-subscription-service')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('custom-service')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('custom-service-name')),
        'Мой книжный клуб',
      );
      await tester.tap(find.byKey(const ValueKey('upload-service-icon')));
      await flushUntil(
        tester,
        () => tester
            .widgetList<ServiceBadge>(find.byType(ServiceBadge))
            .any((b) => b.customIconPath != null),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-custom-service')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Мой книжный клуб',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '500');
      await save(tester, () => controller.data.recurring.length == 1);
      final rule = controller.data.recurring.single;
      expect(rule.serviceId, isNull);
      expect(rule.customIconPath, contains('/service_icons/'));
      final bytes = await tester.runAsync(
        () => File(rule.customIconPath!).readAsBytes(),
      );
      expect(bytes, image);
      final original = await tester.runAsync(
        () => File('${directory.path}/source.png').readAsBytes(),
      );
      expect(original, image);
      final portable = await tester.runAsync(repository.exportJson);
      expect(
        (jsonDecode(portable!) as Map<String, dynamic>)['serviceIcons'],
        contains('recurring:${rule.id}'),
      );
      await tester.runAsync(() => repository.importJson(portable));
      final imported = await tester.runAsync(repository.load);
      expect(
        imported!.recurring.single.customIconPath,
        isNot(rule.customIconPath),
      );
      expect(
        await tester.runAsync(
          () => File(imported.recurring.single.customIconPath!).readAsBytes(),
        ),
        image,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'individual reminder opt-in saves lead and time without changing automation or global preferences',
    (tester) async {
      final rule = RecurringRule(
        id: 'internet',
        name: 'Интернет',
        accountId: 'card',
        categoryId: 'subscriptions',
        amountMinor: 50000,
        paymentType: 'mandatory',
        nextDate: DateTime.now().add(const Duration(days: 10)),
        automatic: true,
      );
      await tester.runAsync(
        () => controller.mutate(
          (d) => d.copyWith(
            recurring: [rule],
            preferences: d.preferences.copyWith(notifications: false),
          ),
        ),
      );
      await mount(
        tester,
        const RecurringScreen(initialPaymentType: 'mandatory'),
      );
      await tester.tap(find.byKey(const ValueKey('payment-rule-internet')));
      await tester.pumpAndSettle();
      expect(notifications.permissionRequests, 0);
      await reveal(
        tester,
        find.byKey(const ValueKey('recurring-reminder-switch')),
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('recurring-reminder-switch')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('recurring-reminder-switch')));
      await tester.pumpAndSettle();
      expect(notifications.permissionRequests, 1);
      await reveal(tester, find.text('За 1 день'));
      await tester.tap(find.text('За 1 день'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('За 7 дней').last);
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const ValueKey('recurring-reminder-time')),
      );
      await tester.tap(find.byKey(const ValueKey('recurring-reminder-time')));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), '18');
      await tester.enterText(fields.at(1), '35');
      await tester.tap(find.text('ОК'));
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.text('Уведомления отключены в настройках приложения.'),
      );
      expect(find.text('Настройки уведомлений'), findsOneWidget);
      await save(
        tester,
        () => controller.data.recurring.single.reminderEnabled,
      );
      final saved = controller.data.recurring.single;
      expect(saved.reminderDaysBefore, 7);
      expect(saved.reminderHour, 18);
      expect(saved.reminderMinute, 35);
      expect(saved.automatic, isTrue);
      expect(saved.enabled, isTrue);
      expect(controller.data.preferences.notifications, isFalse);
      expect(notifications.permissionRequests, 1);
    },
  );

  testWidgets(
    'denied reminder permission leaves reminder disabled and automatic independent',
    (tester) async {
      notifications.permissionAllowed = false;
      await newSubscription(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'Мой сервис');
      await tester.enterText(find.byType(TextFormField).at(1), '100');
      await reveal(
        tester,
        find.byKey(const ValueKey('recurring-reminder-switch')),
      );
      await tester.tap(find.byKey(const ValueKey('recurring-reminder-switch')));
      await tester.pumpAndSettle();
      expect(notifications.permissionRequests, 1);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('recurring-reminder-switch')),
            )
            .value,
        isFalse,
      );
      expect(
        find.textContaining('Разрешите уведомления Finance'),
        findsOneWidget,
      );
      await reveal(
        tester,
        find.byKey(const ValueKey('recurring-automatic-switch')),
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('recurring-automatic-switch')),
            )
            .value,
        isFalse,
      );
      await save(tester, () => controller.data.recurring.isNotEmpty);
      expect(controller.data.recurring.single.reminderEnabled, isFalse);
      expect(controller.data.recurring.single.automatic, isFalse);
    },
  );

  testWidgets(
    'legacy exact brand names use real artwork and uploaded custom art wins',
    (tester) async {
      await mount(
        tester,
        Scaffold(
          body: Row(
            children: [
              const ServiceBadge(name: 'NETFLIX'),
              ServiceBadge(
                name: 'Spotify',
                customIconPath: '${directory.path}/source.png',
              ),
              const ServiceBadge(name: 'Netflix Family'),
            ],
          ),
        ),
      );
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.subscriptions_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'turning a saved reminder off requests no permission and keeps automatic disabled',
    (tester) async {
      final rule = RecurringRule(
        id: 'quiet',
        name: 'Сервис без автосписания',
        serviceId: 'spotify',
        accountId: 'card',
        categoryId: 'subscriptions',
        amountMinor: 10000,
        paymentType: 'subscription',
        nextDate: DateTime.now().add(const Duration(days: 10)),
        reminderEnabled: true,
        reminderDaysBefore: 3,
        reminderHour: 9,
        reminderMinute: 15,
        automatic: false,
      );
      await tester.runAsync(
        () => controller.mutate((d) => d.copyWith(recurring: [rule])),
      );
      await mount(
        tester,
        const RecurringScreen(initialPaymentType: 'subscription'),
      );
      await tester.tap(find.byKey(const ValueKey('payment-rule-quiet')));
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const ValueKey('recurring-reminder-switch')),
      );
      await tester.tap(find.byKey(const ValueKey('recurring-reminder-switch')));
      await tester.pumpAndSettle();
      expect(notifications.permissionRequests, 0);
      await save(
        tester,
        () => !controller.data.recurring.single.reminderEnabled,
      );
      final actual = controller.data.recurring.single;
      expect(actual.automatic, isFalse);
      expect(actual.enabled, isTrue);
      expect(actual.reminderDaysBefore, 3);
      expect(actual.reminderHour, 9);
      expect(actual.reminderMinute, 15);
      expect(notifications.permissionRequests, 0);
    },
  );

  testWidgets(
    'service picker fits a small screen with large text and neutral missing-logo fallback',
    (tester) async {
      await mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showServicePicker(context),
                child: const Text('Сервисы'),
              ),
            ),
          ),
        ),
        scale: 1.5,
        size: const Size(320, 640),
      );
      await tester.tap(find.text('Сервисы'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('service-search')),
        'ОККО',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('service-option-okko')), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byIcon(Icons.subscriptions_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
