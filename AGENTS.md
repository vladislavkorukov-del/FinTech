# AGENTS.md — работа с Finora

Инструкция для агентов (Codex и др.). `CLAUDE.md` в корне — шаблон
ruflo/claude-flow, к этому Flutter-проекту он не относится: команды
`npx …` и `npm run build && npm test` здесь не нужны.

## Что это

Finora — личная и семейная бухгалтерия для Android на Flutter
(пакет `com.finora.fintech`). Версия: `pubspec.yaml` → `version:`
(сейчас 1.0.0+140; в настройках показывается «Finora Release 1.0.0»).
Пользователь общается по-русски; отчёты и тексты интерфейса — на русском.

## Сборка и проверки

```bash
export PATH=/opt/fl/flutter/bin:$PATH FLUTTER_ROOT=/opt/fl/flutter  # путь в облачной среде
flutter analyze                         # должно быть «No issues found»
flutter test                            # все тесты (~750, ~3 мин)
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
- **Следующая — Phase 4: общая система действий** для чата и голоса:
  `AppAction` / `ActionRegistry` / `ActionExecutor` с уровнями риска,
  подтверждением и Undo. Строится на существующих `VoiceCommand` и
  `VoiceCommands.run`, парсер голоса не переписывать. Навигация — через
  существующие `onTab` / `Navigator.push`, без второго роутера.
- Дальше — фазы 5–8 по плану в аудите.

## Необязательная задача: локальная Qwen (не начата, ничего не внедрено)

Пользователь просил разговорного ассистента на Qwen на телефоне
(Samsung Galaxy A56, 8 ГБ), затем отменил. Если вернётся к ней, вот что
проверено 2026-11-18:

- Runtime: MNN-LLM. Карточка 2B-модели указывает проверенный коммит MNN
  `b0239771b07b317a258fbc384683bbd540741406` (MNN 3.6.2). API:
  `transformers/llm/engine/include/llm/llm.hpp` (`Llm::createLLM`,
  `load`, `set_config`, `response(ChatMessages, os, "<eop>", 0)`,
  `generate(1)`, `stoped()`, `getContext()` с `prefill_us`/`decode_us`).
  Пошаговый цикл со стоп-флагом — как в
  `apps/Android/MnnLlmChat/app/src/main/cpp/llm_session.cpp`.
- Модели (Apache-2.0):
  - `taobao-mnn/Qwen3.5-2B-MNN`, ревизия
    `77cc78a9ec864f0a7067a4458c181a9c7c0f0378`: `llm.mnn.weight`
    1 059 043 482 Б, `tokenizer.mtok`. Всего с визуальной частью
    1 271 744 435 Б.
  - `taobao-mnn/Qwen3.5-0.8B-MNN`, ревизия
    `3208b55b2e3c948016c9d380a697be881a1f12f8`: `llm.mnn.weight`
    470 382 614 Б, `tokenizer.txt`. Всего 547 648 308 Б.
  - Размеры и SHA-256 LFS-файлов берутся из
    `https://huggingface.co/api/models/<repo>/tree/<rev>?recursive=true`.
    Для небольших не-LFS файлов SHA-256 нужно посчитать самим.
- Конфиг: thinking выключается через
  `{"jinja":{"context":{"enable_thinking":false}}}`. MNN выбирает
  мультимодальный класс по `is_visual` из `llm_config.json`.
  **Не проверено**, работает ли текст без визуальных файлов, если
  подставить свой `llm_config` с `is_visual:false` (у Qwen3.5 mrope) —
  проверить настоящим запуском.
- В проекте: `minSdk 24`, ABI `arm64-v8a`, NDK 28.2. Нативных LLM-библиотек
  нет. GitHub-страницы через прокси отдают 403, но `git fetch` и
  `raw.githubusercontent.com` работают.
- Требования пользователя: модель выключена по умолчанию, скачивается
  только по кнопке, с manifest и SHA-256, хранится отдельно от БД и
  памяти. Факты — только из движков Finora. Действия — только из реестра,
  с подтверждением. Честно разделять «проверено моделью» и «проверено
  тестами».
