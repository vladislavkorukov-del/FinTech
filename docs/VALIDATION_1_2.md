# Проверка Finance 1.2.0

5 ноября 2026. Подписанный release APK Finance 1.2.0/code3 собран, проверен и упакован в ZIP. Утверждённый PNG из `Finance_icon_5000_rub.zip` встроен в центр шапки, загрузочный экран и Android launcher. Исходный рисунок не перерисовывался и не заменялся.

## Свежие проверки

| Проверка | Результат |
|---|---|
| Flutter / Dart | Flutter 3.47.9 / Dart 3.13.7 |
| Анализатор | `flutter analyze --no-pub`: exit 0, No issues found |
| Формат | `dart format --output=none --set-exit-if-changed lib test`: exit 0, 49 файлов без изменений |
| Тесты | `flutter test --no-pub --reporter expanded`: exit 0, **187 passed, 0 failed** |
| Release build | `flutter build apk --release --no-pub`: exit 0, подписанный универсальный APK с оригинальным PNG |
| Подпись | `apksigner verify --verbose --print-certs`: exit 0, v2, прежний RSA3072 сертификат |
| APK metadata | application-label Finance, com.finora.fintech, versionName 1.2.0, versionCode 3, minSdk 24, targetSdk 36 |
| Логотипы сервисов | `python tool/fetch_service_assets.py --verify`: exit 0, 53 точных SVG; все 53 есть в APK |
| Архив APK/ZIP | `ZipFile.testzip()`: без ошибок; ZIP содержит только Finance.apk, его SHA-256 совпал с исходным APK |
| Утверждённый PNG | Flutter asset и Android source совпадают побайтно с оригиналом; упакованный Flutter asset имеет тот же SHA-256. AAPT losslessly сжал native PNG; проверено полное совпадение декодированных пикселей 1254×1254 и ссылка launcher на этот ресурс |
| Логотип в UI | Настоящий PNG декодирован в widget-тесте обеих тем и двух ширин; отрисован и осмотрен предпросмотр главной с Roboto |
| Diff | `git diff --check`: exit 0 |
| Физический Android | Не подключён; доставка ОС, reboot/Doze и системные разрешения вручную не проверены |

APK: `build/app/outputs/flutter-apk/app-release.apk`, 71,404,590 байт.
APK SHA-256: `e1f4a3863fb66b1a8f144312cbe63b7be05fa3c3744dfda226137d1bf509a7d3`.
ZIP: `releases/v1.2.0/Finance-APK.zip`, 35,667,433 байт.
ZIP SHA-256: `bea21834322f8eead16803f5a10be6fc4b40cf0cc9e95f4a631a984d0cee7e01`.
Сертификат SHA-256: `65c17c4a096d4081db73eafe12b4bc83d0df167ada3a1f98723b7db18d350b42`.
Оригинальный PNG SHA-256: `1520aa31c87f3b5ee37aeed64432be9c8ca4c17bd3fd547329916906799e2388`.

Application ID и сертификат сохранены: пакет предназначен для установки поверх 1.0/1.1 с сохранением локальной базы. ABI: armeabi-v7a, arm64-v8a, x86_64; Android 7.0+. [Предпросмотр](images/finance-1.2.0-dashboard.png) сделан Flutter test renderer с демонстрационными данными, не на физическом телефоне.

Сборка завершилась с предупреждениями Flutter о будущем переходе зависимостей file_picker/package_info_plus/share_plus на Built-in Kotlin и о версиях Android SDK XML. Они не помешали сборке; стек и идентификатор приложения не менялись ради их обхода.

## Требования и доказательства

| Требование | Изменение и проверка | Статус |
|---|---|---|
| Тёплая тема | Coffee-токены и семантические цвета, date/time pickers, диалоги, переключатели и навигация. Проверены обе яркости, контраст и сохранение старого выбора; все 6 прежних пресетов сохранены. Предпросмотр главной отрисован с Roboto. | Подтверждена реализация; полное визуальное сравнение на Android не выполнено |
| Шапка | Абсолютный центр через Stack, настройки слева, семейный профиль справа. Геометрия при 320/412px, настоящий PNG и переход к семье проверены. Глаз и функция скрытия сумм удалены. | Подтверждено widget-тестами и проверкой packaged asset |
| Компоновка | Доход/Расход/Перевод → компактный баланс → Все счета. Равная ширина действий, зона нажатия >=48dp, рабочая форма перевода, история и редактор счёта. | Подтверждено widget-тестами |
| Лишние тексты | Удалены прежние заголовки, слоганы и объяснение hero-баланса; функциональные сообщения сохранены. | Проверено по исходникам и widget-тестам главной |
| Категории | Создание дохода/расхода, название, иконка, поиск, цвета, редактирование, архив/восстановление связанных категорий, удаление несвязанных. История и аналитика сохраняют ID. | Подтверждено UI и реальной SQLite FFI |
| Последняя категория | Раздельные IDs в preferences; обновление атомарно с новой ручной записью. Проверены отмена, успешная запись, редактирование истории, отказ SQLite, повторное открытие и архив. | Подтверждено |
| Подписки | 62 сервиса, 53 настоящих локальных SVG и 9 нейтральных вариантов. RU/EN поиск, пользовательская PNG/JPEG/WebP, перенос через JSON, приоритет загруженного изображения. Автоматические связанные записи сохраняют логотип. | Подтверждены каталог, UI и portable media; не у всех сервисов поставляется фирменный ассет |
| Уведомления | Общий и индивидуальный opt-in, разрешение, 0/1/3/7 дней, время, сумма/дата, reschedule/cancel, DST, конец месяца, коллизии, очередь. UI ждёт explicit sync; ошибка не дублирует сохранённое правило, есть retry без DB commit. | Подтверждено на Dart/MethodChannel; фактическая доставка Android не проверена |
| Полгода | 6 календарных месяцев, обе серии, легенда, детали обеих сумм по нажатию. Проверены пустые месяцы, валюта, pending и исключение переводов. | Подтверждено |
| Кольцо | Все суммы остаются в секторах; иконки/проценты вокруг, независимое переключение на суммы, выбор сектора, детали. Пагинация подписей для 27 категорий, 320px, крупный текст и максимально поддерживаемые суммы. Округление до 100%. | Подтверждено widget-тестами; цвета существующих категорий не заменяются |
| Finance | Название приложения и интерфейса изменено, application ID и файл finora.db сохранены. | Подтверждено исходниками и APK metadata |
| Данные | Аддитивная SQLite 1/2→3, импорт JSON/SQLite 1/2/3; старые темы/настройки, семья, операции, балансы, цели и чеки. | Подтверждено на заполненных SQLite FFI fixtures; база реального телефона не предоставлялась |

## Изменённые участки проекта

- `lib/presentation/theme/app_theme.dart`, `widgets/common.dart`: Coffee, палитра, стили компонентов и форматирование без маскирования.
- `screens/dashboard.dart`, `widgets/finance_header.dart`, `widgets/finance_quick_actions.dart`: шапка, компактная главная и действия.
- `screens/entry_editor.dart`, `screens/management_categories.dart`, `presentation/controller.dart`: собственные категории, безопасный архив, память быстрого выбора и редактирование истории.
- `domain/models.dart`, `data/finance_repository.dart`, `data/demo_data.dart`: схема/модели, миграции, перенос изображений и свежая демонстрационная палитра без изменения существующих данных.
- `domain/service_catalog.dart`, `widgets/service_badge.dart`, `screens/management_recurring.dart`, `assets/services/`, `tool/fetch_service_assets.py`: подписки, реальные ассеты, поиск и пользовательские изображения.
- `services/notification_service.dart`, `screens/settings.dart`, `presentation/controller.dart`: opt-in, календарное планирование, явное ожидание и повторное обновление.
- `screens/analytics.dart`, `widgets/category_orbit_chart.dart`, `widgets/half_year_chart.dart`, `widgets/charts.dart`: обе серии и кольцо с интерактивными подписями, дневные суммы.
- `screens/management_accounts.dart`, `management_budgets.dart`, `management_calendar.dart`, `management_goals.dart`, `management_more.dart`, `widgets/entry_tile.dart`: согласование тем, сумм и рабочих переходов.
- `lib/main.dart`, `services/security_service.dart`, `android/app/src/main/AndroidManifest.xml`, Android `values/styles.xml`/`values-night/styles.xml`, `pubspec.yaml`/lock: Finance, версия 1.2.0+3, ресурсы и SVG-зависимость.
- `assets/brand/`, Android `drawable-nodpi/finance_brand.png` и `drawable/ic_launcher.xml`: утверждённый PNG без перерисовки, метаданные и launcher.
- Новые тесты: `brand_asset_test.dart`, `category_ui_v12_test.dart`, `finance_v12_interface_test.dart`, `service_subscription_ui_test.dart`, `notification_sync_ui_test.dart`. Обновлены domain/repository/notification/theme и существующие UI-регрессии под новый контракт.

## Что не проверено на устройстве

Физический Android не подключён. Отдельно требуются запуск/обновление на телефоне, системный permission-диалог, доставка уведомлений при закрытом приложении, перезагрузка и энергосбережение, биометрия, скриншоты и внешний вид launcher под маской конкретного Android launcher. Локальные тесты и анализ APK не заменяют эти проверки. Проверки миграции выполнялись на заполненных SQLite FFI fixtures, а не на базе реального телефона.

Семейный профиль остаётся локальным, cloud sync не подключён. Напоминания имеют конечный горизонт до 12 повторений на правило и 400 ожидающих уведомлений; детали — [NOTIFICATIONS.md](NOTIFICATIONS.md). Финансовые операции не выполняются самим уведомлением.

История проверки предыдущего релиза: [1.1.0](VALIDATION_1_1.md).
