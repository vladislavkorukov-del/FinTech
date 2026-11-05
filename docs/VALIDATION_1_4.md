# Проверка Finance 1.4.0

5 ноября 2026. Исправлено сохранение новых тем, добавлена прозрачная анимированная F и офлайн-распознавание чеков/банковских скриншотов. Идентификатор `com.finora.fintech`, сертификат, база `finora.db` и схема SQLite version3 сохранены. Миграция не требуется.

## Свежие результаты

| Команда / проверка | Результат |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit0, 66 файлов без изменений |
| `flutter analyze --no-pub` | exit0, No issues found |
| `flutter test --no-pub --reporter expanded` | exit0, **290 passed, 0 failed, 0 skipped** |
| `flutter build apk --release --no-pub` | exit0, подписанный universal APK, assembleRelease72.9s |
| `:app:compileReleaseKotlin` | exit0, постоянные Tesseract4Android/EXIF зависимости и конечный share bridge |
| `python tool/fetch_service_assets.py --verify` | exit0, 246 записей / 246 оригинальных файлов |
| APK assets | 246 сервисов, обе OCR-модели, лицензии и оба PNG Finance сверены с исходниками/SHA-256 |
| Android launcher | Исходник неизменён; все RGBA-пиксели AAPT-сжатого PNG в APK совпали с утверждённым оригиналом |
| Подпись | apksigner verify exit0, прежний RSA3072 сертификат, v2 |
| Метаданные | Finance, com.finora.fintech, versionName1.4.0, code5, minSdk24, targetSdk36 |
| Сеть | Release-манифест не запрашивает INTERNET |
| 16KiB | `zipalign -c -P 16 -v 4` exit0; все arm64 ELF LOAD >=0x4000, включая OCR-библиотеки |
| ZIP | Ровно Finance.apk; CRC и SHA-256 вложенного APK проверены |
| Diff | `git diff --check` чистый |

APK: 98,261,706 байт; SHA-256 `59cb40e456421e4e8ff00e2aa22d8c786df847d2faaa4545a231446cabbec380`.
ZIP: 50,256,010 байт; SHA-256 `e787e585d9dc7a34e5b3af7526a9ce26891836ace6b657a44cce2fbd5bd63f1a`.
Сертификат SHA-256: `65c17c4a096d4081db73eafe12b4bc83d0df167ada3a1f98723b7db18d350b42`.

## Сохранение тем

Причина сообщения «Некорректные настройки приложения» — whitelist repository не содержал Harbor, Forest, Velvet/Lavender, Aurora и Royal, хотя UI уже предлагал эти стили. Добавлены именно эти пять ID. Прежняя версия проверяла отрисовку, но пропустила сохранение новых значений; новый regression воспроизводил отказ до исправления.

Проверены все12 стилей × light/dark/system через настоящие Settings, SQLite save/close/reopen и JSON import. Промежуточные кадры переключения темы и изменение системной яркости проходят без исключений. Исторические aliases сохранены; неизвестное значение отклоняется атомарно, финансовые данные не меняются.

## Шапка

`Finance_F_transparent.png` — удаление фона утверждённого пользовательского PNG через инструмент редактирования изображения. Исходный файл и нативный launcher сохранены. RGBA-прозрачность проверена: углы alpha0, более70% пикселей полностью прозрачны, видимые пиксели F присутствуют. Header остаётся54×54 и строго в центре на320/412dp в обеих темах. Flutter renderer отдельно показал прозрачный знак на тёмной и светлой поверхности.

Мягкий цикл2200ms с паузами, без фоновой плашки. Reduced motion и TickerMode скрытого/заблокированного маршрута отключают движение; dispose очищает timer/controller. Проверены анимация, её отключение и освобождение.

## Распознавание и сохранение

Новая команда **+ → Чек или скриншот**, кнопка в новой операции, галерея/камера и Android ACTION_SEND image/* для одного снимка. Встроены Tesseract4Android4.9.0 и локальные rus+eng модели с SHA-256; сети и API-ключа нет. Ограничения входа20MiB/100MP, уменьшение декодирования до примерно2400px, EXIF-ориентации, один ограниченный worker, отмена доставки результата и закрытие ресурсов.

Parser предлагает итоговую сумму вместо НДС/сдачи/баланса, валюту, магазин, дату и тип. Категория — существующая активная, по истории магазина или RU/EN правилам. Нет автоматического создания категорий или финансовой записи. Нечёткий результат и возможный дубль показывают предупреждение. Неясный перевод требует явного типа; чужая валюта блокирует сохранение до выбора подходящего счёта или явной коррекции валюты пользователем.

- 32 parser checks: чеки RU/EN, multiline банк, комиссии/баланс/сдача, валюты, неоднозначность, история и архивные категории.
- 28 codec checks: реальный Dart↔native контракт, ошибки, ограничение результата, очередь, отмена/поздний ответ, уникальный retry, shared image/event/error consumption.
- 6 интеграционных UI checks: настоящий SQLite/parser/editor, запись только после Save, ожидаемый баланс/последняя категория/сохранённый снимок, неоднозначный перевод, валюта, отмена,320×640/640×360 с textScale1.5, cold-start shared draft. Только native boundary замокан.
- 2 real-engine host checks: OCR настоящим Tesseract с включёнными моделями читает два синтетических изображения чека и банка; проверены итоги244,80/1250,50RUB, магазин, дата и категория, без ручного исправления OCR-текста. Это не проверка Android-бинарника на телефоне.

Изображения сохраняются в private receipts, исходный пользовательский файл не меняется. Отменённые неиспользуемые OCR-копии удаляются; сохранённый снимок остаётся вложением. PIN закрывает весь Navigator, включая OCR-черновик. Лицензии включены в APK и доступны в настройках. [Контракт, источники, ограничения](OCR.md).

## Затронутые файлы

- `lib/data/finance_repository.dart`: whitelist новых тем.
- `lib/presentation/widgets/finance_header.dart`, `assets/brand/*`: прозрачная F, движение, provenance; исходный PNG неизменён.
- `lib/domain/receipt_parser.dart`, `scan_draft.dart`: независимый разбор OCR в черновик.
- `lib/services/receipt_ocr_service.dart`, `receipt_share_service.dart`, `receipt_image_store.dart`: native-контракты и приватные снимки.
- `lib/presentation/screens/entry_editor.dart`, `lib/main.dart`: ввод, просмотр результата, ручная проверка, save, share и блокировка.
- `android/app/src/main/kotlin/com/finora/fintech/ReceiptOcr*.kt`, `ReceiptShareBridge.kt`, `MainActivity.kt`, Manifest, оба Gradle scripts: офлайн Android OCR, EXIF и share target.
- `assets/ocr/*`, `pubspec.yaml`, Settings: модели, notices, лицензии, версия1.4.0+5.
- Новые parser/codec/UI/theme/host tests и fixtures; `brand_asset_test.dart` расширен. В прежнем `finance_v12_interface_test.dart` Save ищется прокруткой lazy-списка после добавления OCR-кнопки — проверки сохранены.
- README, SECURITY, OCR, отчёт; `releases/v1.4.0/*`: подписанная сборка в ZIP и контрольные суммы.

## Непроверенное и ограничения

`adb devices -l` пуст: на физическом Android/эмуляторе не проверены камера/системный photo picker, реальный Android Share cold/warm lifecycle, EXIF-примеры на устройстве, скорость/качество OCR и установка поверх предыдущей версии. Нативный код скомпилирован, Dart/UI и реальные модели проверены доступными средствами; это не заменяет эти сценарии. Уведомления и биометрия на устройстве также не перепроверены. Точность на любом банковском шаблоне или нечётком чеке не гарантируется.

Отмена немедленно блокирует выдачу результата; уже запущенный нативный UTF8 OCR безопасно завершает работу на своём worker перед recycle, а не принудительно останавливает CPU. Лимит переносимого JSON прежний:10MiB на изображение и30MiB общих медиа; более крупное вложение потребует уменьшения перед экспортом. Старые финансовые и семейные regression checks входят в290 passed.

Сборка завершилась с прежним предупреждением Flutter о будущей миграции file_picker/package_info_plus/share_plus на Built-in Kotlin. Проверки не отключались.

Предыдущие отчёты: [1.3.0](VALIDATION_1_3.md), [1.2.0](VALIDATION_1_2.md), [1.1.0](VALIDATION_1_1.md).
