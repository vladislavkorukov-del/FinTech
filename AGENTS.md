# AGENTS.md — работа с Finora

Инструкция для агентов (Codex и др.). `CLAUDE.md` в корне — шаблон
ruflo/claude-flow, к этому Flutter-проекту он не относится: команды
`npx …` и `npm run build && npm test` здесь не нужны.

## Что это

Finora — личная и семейная бухгалтерия для Android на Flutter
(пакет `com.finora.fintech`). Версия: `pubspec.yaml` → `version:`
(сейчас 1.0.0+142; в настройках показывается «Finora Release 1.0.0»).
Пользователь общается по-русски; отчёты и тексты интерфейса — на русском.

## Сборка и проверки

```bash
export PATH=/opt/fl/flutter/bin:$PATH FLUTTER_ROOT=/opt/fl/flutter  # путь в облачной среде
flutter analyze                         # должно быть «No issues found»
flutter test                            # все тесты (>900, ~3 мин)
flutter test test/finora_ai_test.dart   # точечно
flutter build apk --release             # arm64-v8a
```

Проверка APK:

```bash
/opt/android-sdk/build-tools/36.0.0/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
/opt/android-sdk/build-tools/36.0.0/aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk | head -1
```

- Подпись: `android/key.properties` и keystore лежат локально и в git не
  входят. Без них release собирается неподписанным. Сертификат должен
  совпадать с прежним (SHA-256 `65c17c4a…0b42`), иначе обновление поверх
  установленной версии не встанет.
- Перед каждой сборкой для пользователя увеличивайте `+N` в `version:`.
- Тесты кладите в `test/`. После `dart format` прогоняйте `flutter analyze`.
- Место на диске в облачной среде ограничено: удаляйте `build/` и
  `android/.kotlin` перед сборкой и не храните старые APK.

## Правила

- Делать то, что попросили. Новые файлы и документацию — только когда
  нужно или просят.
- Старые сохранения должны открываться. Схема БД меняется только через
  миграции в `FinanceRepository` (`schemaVersion`, `onUpgrade`); новые
  поля моделей читаются с значениями по умолчанию.
- **Голосовой помощник не переписывать** (`voice_command_parser.dart`,
  `voice_commands.dart`, `voice_entry_parser.dart`, нативный `finora/voice`).
- Мира Финоры, игр, игровой валюты и прогрессии нет и не возвращать.
  Достижения (`achievements.dart`) остаются — они за действия в учёте.
- Кругляш (orb) на главный экран не возвращать.
- Никакого облака и платных сервисов. Финансовые данные и память AI не
  уходят в сеть.
- Не коммитить секреты, `key.properties`, keystore, `.env`.
- В коммитах не ставить трейлер `Co-Authored-By`.
- Финансовые суммы — целые копейки (`amountMinor`), без `double` для денег.

## Структура

```
lib/
  main.dart                 Bootstrap → FinoraApp → HomeShell (вкладки 0/1/3/4/5,
                            боковое меню FinoraDrawer, история вкладок, «назад»)
  data/                     FinanceRepository (sqflite, миграции, JSON/CSV, бэкап)
  domain/                   модели, FinanceEngine, каталоги, парсеры,
                            payment_plan (кредиты с процентами), shopping,
                            duplicate_detector
  presentation/             контроллер (ChangeNotifier + FinanceScope), экраны,
                            виджеты, тема, переводы (l10n_table.dart)
  features/finora_ai/       локальный AI (офлайн):
    services/               AiContext, FinoraAiSnapshot (все факты), FinoraAi,
                            smart_notifications
    classification/         TransactionClassifier, MerchantIntelligence
    detectors/              Recurring, Anomaly, Refund
    forecasting/            Forecast, Cashflow (+таймлайн)
    insights/               InsightEngine, MonthComparison, BudgetRisk,
                            FinancialPattern, Recommendation, FinancialHealth
    memory/ repositories/   PersonalMemory (JSON-файл отдельно от БД)
    responses/              IntentParser, ResponseLayer (шаблоны), capabilities
    ui/ widgets/            окно Finora AI, «Анализ», настройки AI, помощь
  services/                 уведомления, безопасность, голос, OCR (нативные каналы)
android/app/src/main/kotlin/…  мосты: голос, «ухо», OCR, виджеты, шеринг
tool/finora_ai/             Python-пайплайн обучения классификатора
```

Главный принцип AI: **сначала факты из движков, потом слова**.
`ResponseLayer` не считает и не выдумывает числа.

## Состояние и план

Подробно — `docs/FINORA_AI_AUDIT.md`: аудит по пунктам ТЗ, архитектура и
разделы «Phase 1/2/3 — сделано».

- Сделаны фазы 0–3: аудит; инсайты с трассировкой и ранжированием;
  сравнение периодов; классификатор с источниками и порогами (`AiConfig`);
  merchant intelligence и автодополнение; настройки AI и сброс
  персонализации; подписки, подушка, индекс стабильности, мечты, возвраты,
  дубли, умные уведомления.
- **Phase 4:** восемь typed actions с рисками, whitelist, уточнениями одного
  черновика, TTL5min, отменой и сохранением consumed IDs; штатная форма операций.
  Недельный план долгов — `domain/weekly_debt_plan.dart`, pending FinanceEntry
  со связью с RecurringRule, schema8. Только posted уменьшает баланс и долг.
  Изменение/удаление проведённой выплаты согласует договорную дату заново.
  Подтверждённые предпочтения и typed сценарии — schema4 PersonalMemory,
  старые merchants/коррекции сохраняются. Сценарии используют текущую БД,
  автоматически по расписанию не запускаются. Описание/проверки:
  `docs/PHASE4.md` и `docs/PHASE4_VERIFICATION.md`.
- Дальше — фазы 5–8 по плану в аудите.

## Необязательная локальная Qwen (эксперимент, build 141)

Реализация и воспроизведение — `docs/LOCAL_QWEN.md`, результаты проверок —
`docs/LOCAL_QWEN_VERIFICATION.md`. Перед изменением runtime прочитайте оба.

- MNN CPU 3.6.2 закреплён на `b0239771b07b317a258fbc384683bbd540741406`;
  build-time source: `bash tool/local_llm/prepare_mnn.sh`, `.native/` игнорируется.
- Две Qwen3.5 MNN 4-bit ревизии, размеры и SHA находятся в
  `assets/ai/local_models.json`. Веса не включать в git/APK.
- Установка опциональна, выключена по умолчанию. Отдельные файлы
  настроек/весов/истории; финансовая БД и память не зависят от модели.
- `local_model` — доставка, runtime bridge, протокол, история и диагностика;
  Android `local_llm` — один worker, реальный MNN, stop и queued unload.
- Настоящие text-only host probes обеих моделей выполнены. Greedy,
  enable_thinking=false, 2048 токенов вместе с резервом 256 на ответ.
  A56 не проверен; не называть скорость/память host измерениями телефона.
- Legacy 0.8B tokenizer воспроизводимо падает на очень длинном слове
  в std::regex. Сохранять pre-tokenizer input guard в Session::tokenize;
  `lifecycle_probe.cpp` проверяет guard, overflow, stop/reuse/release.
- Факты и числа — только существующие движки, команды — только whitelist,
  полная проверка, подтверждение и штатная форма. Никакого SQL/кода от модели.
- При изменении протокола прогнать `local_assistant_protocol_test.dart`,
  `ai_actions_test.dart`, `local_model_download_test.dart` и реальный probe.
  Тестовый адаптер не доказывает инференс. Проверить APK/подпись/16 KiB.
- Старт диагностики: О приложении → версия, три отдельных удержания
  >=1.5 с за 12 с. По умолчанию метаданные без текстов; экспорт без весов.

## Доставка моделей после Phase 4 (build 142)

`ModelDownloader` использует канонический resolve, bounded retry и `.part`
metadata/validators. `phase4_downloader_http_test.dart` — настоящий loopback HTTP,
не подменённый транспорт. Прерывание в фоне — пауза; системный background worker
не добавлен. Все signed URL/Authorization очищать в diagnostics и user_error;
сырой exception не показывать. Установлено/включено/runtime loaded — разные состояния.
Ревизии и runtime не менять без отдельных проверок и реального inference.
