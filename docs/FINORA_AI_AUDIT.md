# Finora AI — аудит перед развитием (Phase 0)

Аудит сделан по коду ветки на версии 1.0.0+137 (134 файла Dart в `lib/`).
Цель — не строить второе приложение рядом с первым: у каждого пункта ТЗ
указано, что уже есть, и что с этим делать.

## 1. Текущая архитектура

```
UI (Flutter, Material 3, свой стиль)
  main.dart: Bootstrap → FinoraApp (MaterialApp) → HomeShell
  HomeShell: вкладки по индексу (0 главная, 1 операции, 3 аналитика,
             4 ещё, 5 Finora AI) + боковое меню FinoraDrawer;
             внутренние экраны — Navigator.push(MaterialPageRoute)
        │
State: FinanceController (ChangeNotifier) + FinanceScope (InheritedNotifier)
        │  все изменения через controller.mutate / saveX / deleteX
Data:  FinanceRepository (sqflite, схема с миграциями onUpgrade,
       JSON/CSV экспорт-импорт, бэкап файла БД)
        │
Domain: models.dart (Account, Category+subcategories, FinanceEntry,
        Budget, Goal, RecurringRule, AppPreferences, ShoppingItem),
        finance_engine.dart (балансы, бюджеты, цели), каталоги сервисов,
        магазинов и банков, парсеры (голос, чеки, выписки, CSV)
        │
Services: уведомления, безопасность (local_auth + secure storage),
        голос (системный диалог через MethodChannel finora/voice),
        «ухо» Финоры (wake word), OCR (Tesseract в нативном коде)

lib/features/finora_ai/  — локальный AI (сделан ранее, офлайн)
  services/  AiContext (подготовка данных), FinoraAiSnapshot (все факты
             одним расчётом), FinoraAi (фасад: ready/classify/answer)
  classification/ TransactionClassifier, CategoryMapper
  memory/ PersonalMemory, repositories/ MemoryRepository (JSON-файл)
  personalization/ Feedback (обучение на сохранениях и исправлениях)
  inference/ LinearModel + features (модель из assets/ai)
  detectors/ RecurringDetector, AnomalyDetector
  forecasting/ ForecastEngine, CashflowEngine
  insights/ InsightEngine, MonthComparisonEngine, BudgetRiskEngine,
            FinancialPatternEngine, RecommendationEngine
  responses/ IntentParser, ResponseLayer (шаблоны, без своих чисел)
  ui/ FinoraAiScreen (приветствие / слушание / чат), AnalysisSheet
tool/finora_ai/ — Python-пайплайн обучения (dataset, features, train)
```

Голосовой помощник: `VoiceInputService` (распознавание речи системой)
→ `VoiceEntryParser` (операции) / `VoiceCommandParser` (команды:
тема, показать операции, открыть экран, создать цель/счёт/бюджет/
категорию/регулярный платёж, перевод) → `VoiceCommands.run`
(исполняет, показывает «Готово · Отменить»). **Не переписывается.**

### Остатки игровых систем

- Мира Finora, мини-игр и игровой экономики в Dart-коде нет.
- В нативном Android-коде остались `MagAudioBridge.kt` и
  `FlowAudioBridge.kt`, это звук удалённых игр. Они регистрируются в
  `MainActivity`, но из Dart их никто не вызывает. Предлагаю удалить их
  отдельным коммитом.
- Раздел «Достижения» (`domain/achievements.dart`,
  `achievements_screen.dart`) построен на наградах, редкости и уровнях,
  то есть это игровая прогрессия. По новой концепции её быть не должно,
  но удаление — продуктовое решение, поэтому прошу подтверждения.

## 2. Таблица статусов

Статусы: DONE, PARTIAL, MISSING, NEEDS_REFACTOR, NOT_APPLICABLE.

### Основа приложения

| Функция | Статус | Что есть | Действие |
|---|---|---|---|
| Архитектура / state management | DONE | ChangeNotifier + InheritedNotifier, контроллер — единая точка изменений | Оставить |
| Локальная БД, миграции | DONE | sqflite, `schemaVersion`, `onUpgrade` | Оставить; AI-таблицы не нужны (память в JSON) |
| Repository layer | DONE | FinanceRepository | Оставить |
| Операции: доход / расход / перевод | DONE | FinanceEntry + EntryKind | Оставить |
| Счета, категории, подкатегории | DONE | Account, Category.subcategories | Оставить |
| Бюджеты, цели (мечты) | DONE | Budget, Goal (+срок, фото) | Оставить |
| Регулярные / обязательные платежи, подписки | DONE | RecurringRule (paymentType, serviceId, напоминания) | Оставить |
| Уведомления | PARTIAL | напоминания о платежах, бюджет 90 % / 100 %, цель достигнута; дедупликация по ключу | Phase 3: приоритет, cooldown, новые типы |
| Аналитика, графики | DONE | AnalyticsScreen, charts, orbit chart, полугодие | Оставить |
| Отчёты | PARTIAL | экспорт CSV/JSON, аналитика по периодам | Phase 7: AI-отчёты |
| Поиск и фильтры операций | PARTIAL | текст + тип / категория / счёт / тег / период / сумма | Phase 4: принимать фильтры извне, сортировка |
| Импорт | PARTIAL | CSV своих и чужих приложений, импорт счетов, выписки по скриншотам | Phase 7: адаптеры XLSX/PDF |
| Экспорт, бэкап | DONE | CSV, JSON, файл БД | Добавить память AI в бэкап (Phase 2) |
| Облачная синхронизация | NOT_APPLICABLE | нет | Не делать; память уже сериализуема |
| Аутентификация | DONE | локальная блокировка (биометрия / PIN) | Оставить |
| Распознавание речи | DONE | системный диалог (`finora/voice`), wake word (`finora/ear`) | Не трогать |
| Синтез речи (TTS) | MISSING | Финора отвечает текстом и анимацией | Не добавлять без запроса (ТЗ: «если уже есть») |
| Персонаж Финоры | DONE | FinoraCharacter / orb, `Finora.reactions`, FinoraSays | Связать с AI-событиями (Phase 6) |
| OCR чеков | DONE | Tesseract локально + ReceiptParser | Оставить |
| Распознавание скриншотов банка | DONE | ScanImport + BankStatementParser | Оставить |
| Темы оформления | DONE | 14 пресетов, light / dark / system | Оставить |
| Доступность | PARTIAL | вибрация вкл./выкл., учёт системного «уменьшить движение» | Phase 4: размер шрифта, анимации в приложении |
| Навигация / роутер | PARTIAL | индексы вкладок + Navigator.push, без именованных маршрутов | Phase 4: AppRoute поверх существующего |
| Deep links | MISSING | — | Phase 4 (optional) |
| Команды / действия | NEEDS_REFACTOR | VoiceCommand + VoiceCommands.run: работает, но привязано к голосу и исполняет без уровней риска | Phase 4: поднять в общий Action System без переписывания парсера |
| Подтверждения | PARTIAL | «Готово · Отменить» после голосовых команд, диалоги удаления в UI | Phase 4: уровни риска |
| Кэширование / фон | PARTIAL | снимок AI кэшируется по ссылке на данные; расчёт в UI-потоке | Phase 8: изолят для больших историй |

### ТЗ по пунктам

| # | Функция | Статус | Что есть | Действие |
|---|---|---|---|---|
| 1 | TransactionClassifier | PARTIAL | память → история → каталог → модель, top-3, confidence | Phase 2: источники exact/merchant/statistical/fallback, пороги в конфиге, время/сумма в признаках |
| 2 | Локальная ML-модель | PARTIAL | линейная модель (JSON 300 КБ), Python-пайплайн, метрики, версия | Phase 5: признаки суммы/времени, schemaVersion, инференс вне UI |
| 3 | PersonalMemory | PARTIAL | merchant→категория (веса), исправления, отказы, подтверждённые подписки | Phase 2: типичные суммы, регулярный доход, предпочтения AI, cooldown инсайтов |
| 4 | Feedback learning | DONE | Feedback.observeSave, отказ «до новых данных» | Оставить, расширить вместе с памятью |
| 5 | InsightEngine | PARTIAL | 16 видов, приоритеты | **Phase 1:** id, severity, confidence, дедупликация, traceability, отбор топа, cooldown |
| 6 | ForecastEngine | PARTIAL | расходы / доход / баланс до конца периода, «мало данных» | **Phase 1:** confidence; Phase 3: по категориям |
| 7 | MonthComparisonEngine | PARTIAL | месяц к месяцу «по равному числу дней», драйверы | **Phase 1:** день / неделя / месяц / квартал / год / свой период, доход и cashflow |
| 8 | RecurringPaymentDetector | PARTIAL | неделя / месяц / год, допуск по сумме и датам | **Phase 1:** 2 недели, квартал, регулярный доход, изменение суммы |
| 9 | SubscriptionDetector | PARTIAL | внутри RecurringDetector: известный сервис или стабильная месячная сумма | Phase 3: исключать аренду, кредиты, ЖКУ по категории и paymentType |
| 10 | AnomalyDetector | PARTIAL | медиана + MAD по категории, новый merchant | **Phase 1:** база по merchant, число операций, объяснение причины |
| 11 | FinancialPatternEngine | DONE | тренды категорий, стабильность дохода, необычные месяцы, сезонность, привычки | Phase 3: рост подписок / обязательных |
| 12 | BudgetRiskEngine | DONE | вероятность, перерасход по темпу | Phase 3: безопасный остаток в день |
| 13 | Smart budgets | DONE | RecommendationEngine.budgets по медиане | Оставить |
| 14 | Goals AI | PARTIAL | нужный взнос в месяц | Phase 3: дата достижения, взнос в неделю, what-if |
| 15 | CashflowEngine | PARTIAL | баланс − обязательные − ожидаемые траты + ожидаемый доход | **Phase 1:** таймлайн событий с датами и прогнозным балансом |
| 16 | Payment calendar | PARTIAL | календарь из RecurringRule (management_calendar) | Phase 3: добавить найденные регулярные платежи с confidence |
| 17 | Missing payment | MISSING | — | **Phase 1:** «обычно уже был» в таймлайне |
| 18 | Subscription analytics | PARTIAL | сумма подписок в RecurringScreen | Phase 3 |
| 19 | Free cash forecast | DONE | CashflowEngine.afterMandatory / afterAll | Оставить |
| 20 | Финансовая подушка | MISSING | — | Phase 3 (без инвестсоветов) |
| 21 | Stability score | MISSING | — | Phase 3, optional, объяснимый |
| 22 | What-if | MISSING | — | Phase 7 |
| 23 | Smart search | PARTIAL | голос «покажи расходы за июнь» → TransactionsScreen с фильтрами | Phase 7: сумма, сортировка, текстом из чата |
| 24 | Semantic search | NOT_APPLICABLE | — | Не добавлять: модель эмбеддингов ≥ 20–90 МБ ради малой пользы |
| 25 | AI-теги | PARTIAL | ручные теги у операций | Phase 7: предлагать, не меняя категорию |
| 26 | Многоуровневые категории | DONE | категория → подкатегория | Третий уровень не делать (сломает схему и UI) |
| 27 | Merchant intelligence | PARTIAL | PayeeSummary (ключ, суммы, частота), каталоги и ServiceRecognizer | Phase 2: алиасы «PYATEROCHKA #123», типичная сумма |
| 28 | Autocomplete | PARTIAL | узнавание сервиса и категории по названию (с 1.0.0+137 без подмены текста) | Phase 2: подсказки merchant, суммы, счёта |
| 29 | Smart input suggestions | PARTIAL | последняя категория, категория по магазину | Phase 2 |
| 30 | Переводы | DONE | EntryKind.transfer не входит в доходы и расходы | Оставить |
| 31 | Возвраты | PARTIAL | «возврат» распознаётся как доход | Phase 3: связка с расходом, вне «дохода» в аналитике |
| 32 | Дубликаты | PARTIAL | при импорте CSV и скриншотов | Phase 3: при ручном вводе — предупреждение |
| 33 | Import intelligence | PARTIAL | маппинг колонок, категории, дубли | Phase 7: адаптеры |
| 34 | OCR чеков | DONE | см. выше | Оставить |
| 35 | Скриншоты банка | DONE | см. выше | Оставить |
| 36 | AI-отчёты | MISSING | — | Phase 7 |
| 37 | Digest | MISSING | — | Phase 7 |
| 38 | Smart notifications | PARTIAL | см. «Уведомления» | Phase 3 |
| 39 | Приоритет блоков главной | PARTIAL | порядок блоков настраивается вручную | Phase 6: поднимать важный инсайт |
| 40 | Персонализация по поведению | MISSING | — | Optional, Phase 6 |
| 41 | Predicted next action | MISSING | — | Optional, Phase 6 |
| 42 | IntentParser | PARTIAL | 13 намерений, правила; команды — отдельный голосовой парсер | Phase 4: единый вход, период/категория/фильтры |
| 43 | Finora AI chat | DONE | FinoraAiScreen | Подключить к Action System (Phase 4/6) |
| 44 | Response layer | DONE | шаблоны, числа только из движков | Оставить |
| 45 | Контекст разговора | MISSING | — | Phase 6 |
| 46–65 | App control / Action System | PARTIAL | голосовые команды: тема, экраны, фильтры операций, создание сущностей, Undo | Phase 4: AppAction, ActionRegistry, риски, Executor, AppContext |
| 66 | Голос + AI | PARTIAL | голос внутри AI-экрана задаёт вопросы | Phase 6: из голосового помощника — вопросы к движкам |
| 67 | Speech-to-text | DONE | — | Не дублировать |
| 68 | Text-to-speech | MISSING | — | Не добавлять второй слой (его нет вообще) |
| 69 | Offline-first | DONE | весь AI локальный | Оставить |
| 70 | Optional cloud AI | MISSING | — | Phase 6: только интерфейс AiProvider, выключен |
| 71–72 | Синхронизация памяти | NOT_APPLICABLE | синхронизации нет; память в JSON | Включить в бэкап |
| 73 | Приватность | DONE | ничего не уходит в сеть | Оставить |
| 74 | Локальная безопасность | PARTIAL | БД и память в песочнице приложения, без шифрования; ключи в secure storage | Не придумывать криптографию |
| 75 | Сброс персонализации | MISSING | — | Phase 2 (+подтверждение) |
| 76 | Explainable AI | PARTIAL | объяснение категории есть | **Phase 1:** причина у инсайтов и аномалий |
| 77 | Traceability | MISSING | — | **Phase 1** |
| 78 | Confidence | PARTIAL | у классификации, рисков, регулярных | **Phase 1:** у инсайтов и прогноза |
| 79 | Adaptive AI | DONE | пороги «мало данных» во всех движках | Оставить |
| 80 | Необычный месяц | PARTIAL | находится | Phase 3: вопрос «учитывать в прогнозах?» |
| 81 | Тренды категорий | DONE | — | Оставить |
| 82 | Будни / выходные | PARTIAL | самый дорогой день недели | Phase 3 |
| 83 | После зарплаты | MISSING | — | Optional |
| 84 | Привычки трат | PARTIAL | топ мест, день недели | Phase 3 |
| 85–86 | Рекомендации | PARTIAL | бюджеты, взносы по целям; без инвестсоветов | Phase 3 |
| 87 | Summary заметок | NOT_APPLICABLE | заметки короткие | Не делать |
| 88 | Local embeddings | NOT_APPLICABLE | — | См. п. 24 |
| 89–90 | Производительность, батарея | PARTIAL | без фоновых расчётов, снимок по событию | Phase 8 |
| 91 | Размер приложения | — | модель 300 КБ, новых зависимостей нет | — |
| 92 | Fallback | DONE | без модели работает | Оставить |
| 93 | Версии модели | PARTIAL | modelVersion | Phase 5: schemaVersion, preprocessingVersion |
| 94 | Миграции | DONE | sqflite onUpgrade; память — JSON с допуском полей | — |
| 95 | Тесты | PARTIAL | test/finora_ai_test.dart, finora_ai_screen_test.dart, parity | Расширять в каждой фазе |
| 97–98 | Настройки AI, уровни автоматизации | MISSING | — | Phase 2/4 |
| 99 | Реакции персонажа | PARTIAL | реакции на запись / ошибку | Phase 6 |
| — | Long press на персонажа → AI | NOT_APPLICABLE | шар с главного убран по решению владельца; AI открыт пунктом меню «Finora AI» | Вернуть, когда шару найдут место |
| — | «Что ты умеешь» + обучение в настройках | MISSING | есть «Голосовые команды» | **Сделано в этом коммите** |

## 3. Системы под другим названием

| В ТЗ | В Finora |
|---|---|
| Merchant system | `PayeeSummary` + `ServiceCatalog` / `StoreCatalog` / `ServiceRecognizer` |
| SubscriptionDetector | `RecurringDetector.subscriptions` |
| Smart budgets | `RecommendationEngine.budgets` |
| Payment calendar | `management_calendar.dart` + `domain/payment_plan.dart` |
| Free cash | `Cashflow.afterMandatory / afterAll` |
| AppAction / Executor (зародыш) | `VoiceCommand` (sealed) + `VoiceCommands.run` |
| Undo | `added(context, text, undo)` в голосовых командах и SuccessBurst |

## 4. Что переиспользовать, что расширять, что создавать

- **Переиспользовать без изменений:** FinanceController, FinanceRepository,
  FinanceEngine, VoiceInputService, VoiceEntryParser, OCR, каталоги,
  ResponseLayer (подход), FinancialPatternEngine, BudgetRiskEngine.
- **Расширить:** Insight (поля и ранжирование), MonthComparisonEngine
  (любые периоды), RecurringDetector (каденции, доход), AnomalyDetector
  (merchant, частота, причина), CashflowEngine (таймлайн), Forecast
  (confidence), PersonalMemory (суммы, cooldown, предпочтения),
  IntentParser (сущности и действия), TransactionsScreen (сортировка,
  сумма извне).
- **Создать (только этого нет):** AppAction + ActionRegistry +
  ActionExecutor + AppContext (Phase 4, оборачивает VoiceCommands, не
  заменяет), WhatIfEngine (Phase 7), ReportBuilder (Phase 7),
  AiSettings в AppPreferences (Phase 2).

## 5. Лишнее и дублирующее в ТЗ

- **Semantic search / embeddings (24, 88).** Компактная модель весит
  20–90 МБ и требует нативного рантайма. Финансовые запросы
  структурированы: период, категория, сумма, магазин. Правил и фильтров
  достаточно.
- **TFLite (2).** Классификатор — линейная модель на хэшированных
  n-граммах, 300 КБ JSON, считается за микросекунды на чистом Dart.
  TFLite добавил бы около 1–3 МБ нативных библиотек на ABI и плагин без
  выигрыша в точности на этой задаче. Переход оправдан только при смене
  модели (например, на маленький MLP по эмбеддингам).
- **Отдельный SubscriptionDetector.** Это фильтр поверх
  RecurringDetector, не отдельная система.
- **TTS (68).** Его нет. ТЗ запрещает создавать второй слой; первый
  слой без запроса не добавляю.
- **Третий уровень категорий (26).** Схема `subcategories` двухуровневая,
  менять её ради этого — риск для данных и UI.
- **Summary заметок (87).** Заметки однострочные.
- **Cloud sync (71).** Вне AI-модуля по ТЗ.

## 6. Data flow и AI-архитектура

```
FinanceData (контроллер)
   ↓ событие изменения данных (notifyListeners)
AiContext — подготовка один раз: posted, база валюты, периоды
   ↓
Движки (чистые функции, без UI): Comparison, Recurring(+Subscriptions),
Anomaly, Forecast, Cashflow(+timeline), BudgetRisk, Patterns,
Recommendation, Classifier(+PersonalMemory, LinearModel)
   ↓
FinoraAiSnapshot — все факты одним объектом, кэш по ссылке на данные
   ↓
InsightEngine — отбор, ранжирование, дедуп, cooldown, traceability
   ↓
IntentParser → (QueryResolver → ResponseLayer) | (ActionResolver → Action System)
   ↓
Finora AI чат · голосовой помощник · главный экран · уведомления
```

Ответный текст собирается только из полей снимка. ResponseLayer не
считает.

## 7. PersonalMemory

JSON-файл `finora_ai_memory.json` в каталоге поддержки приложения,
отдельно от БД. Сейчас хранит:

- merchant → голоса за категории (вес, дата);
- историю исправлений;
- отказы с «доказательством» (скрыто, пока не появились новые данные);
- подтверждённые подписки и регулярные платежи.

Phase 2 добавляет:

- типичную сумму merchant;
- регулярный доход;
- предпочтения AI;
- `shownInsights` для cooldown;
- `schemaVersion`.

Сериализуемость позволяет положить память в бэкап и будущую
синхронизацию. Сброс персонализации удаляет только этот файл, операции
не трогает.

## 8. ML

Python: `dataset.py` (синтетика и словари) → `features.py` (нормализация,
хэш-n-граммы) → `train.py` (логистическая регрессия, split по
непересекающимся merchant, метрики, экспорт JSON с версией) →
`assets/ai/finora_classifier.json`.

Dart: `LinearModel.parse` лениво при первом обращении. Без файла
работают память, история и каталог.

Phase 5:

- признаки суммы, дня недели и времени;
- `schemaVersion` и `preprocessingVersion`;
- тест паритета Python ↔ Dart (уже есть: `test/fixtures/finora_ai_parity.json`);
- перенос загрузки и инференса в изолят.

## 9. AppAction (Phase 4)

```
Chat / Voice
  → IntentParser (вопрос?) ──→ QueryResolver → ResponseLayer
  → VoiceCommandParser (команда?)  ← существующий парсер, без изменений
  → ActionResolver: VoiceCommand | новый разбор → AppAction
       AppAction{id, type, parameters, riskLevel, requiresConfirmation,
                 source: chat|voice|system, createdAt}
  → ActionRegistry: только зарегистрированные типы
       (navigate, go_back, open_account, open_category, change_theme,
        change_filter, change_sort, create_* / edit_* / delete_*,
        open_settings, change_ai_settings …)
  → Confirmation: LOW сразу; MEDIUM — ActionProposal «Поставить …?»;
                  HIGH — всегда явное подтверждение
  → ActionExecutor.execute(action) → FinanceController / Navigator /
       существующие экраны → ActionResult{success, message, error,
       affectedEntity, navigationTarget, undoToken}
```

`VoiceCommands.run` становится исполнителем для типов, которые уже
поддерживает. Голосовой парсер и UX голоса не меняются, команды из чата
идут тем же путём.

### Навигация

AppRoute — перечень экранов поверх существующих: индексы вкладок
HomeShell и конструкторы экранов (TransactionsScreen принимает фильтры).
Параллельного роутера не будет. Executor вызывает те же `onTab` и
`Navigator.push`, что голосовые команды сейчас.

### AppContext

Текущий экран, выбранная операция, активные фильтры, тема, последний
результат AI. Короткая история — 5 шагов, затем сброс.

## 10. Зависимости и размер

Новых зависимостей не нужно. Модель — 300 КБ. Если в Phase 7 понадобится
XLSX, пакет `excel` добавит около 0,3 МБ Dart-кода; PDF-выписки — только
через уже существующий OCR. TFLite и эмбеддинги не добавляются
(обоснование в п. 5).

## 11. Миграции

Таблицы БД под AI не нужны. Память — JSON с `schemaVersion` и мягким
чтением неизвестных полей. Настройки AI (Phase 2) — новые поля
AppPreferences в таблице `settings` (ключ-значение), значения по
умолчанию для старых сохранений.

## 12. Риски и производительность

- Снимок AI считается в UI-потоке. На 100 000+ операций это сотни
  миллисекунд. Решение (Phase 8): изолят, инкремент по месяцам, кэш.
- AnomalyDetector и RecurringDetector проходят всю историю за год. Это
  O(n), допустимо; на больших данных — индекс по merchant.
- Action System даёт AI право менять данные. Митигация — реестр,
  уровни риска, подтверждение, Undo.
- Ложная уверенность. Митигация — пороги «мало данных» и confidence
  везде.
- Optional: облачный AI, семантический поиск, stability score,
  персонализация по поведению, deep links.

## 13. План по фазам

| Фаза | Содержание |
|---|---|
| 0 | Этот аудит |
| 1 | Структура инсайта (id, severity, confidence, dedup, reason, period, related, calculationVersion), отбор топа и cooldown; сравнение любых периодов; регулярные: 2 недели / квартал / доход / смена суммы; аномалии по merchant и частоте с причиной; таймлайн cashflow + «обычно уже был»; confidence прогноза. **+ «Что ты умеешь» и экран обучения Finora AI** |
| 2 | Классификатор: источники и пороги в конфиге; merchant-алиасы и типичные суммы; память v2; автодополнение; настройки AI; сброс персонализации; память в бэкапе |
| 3 | Подписки отдельно от аренды/кредитов; риски бюджета в день; цели (дата, неделя); календарь с найденными платежами; аналитика подписок; подушка; возвраты; дубли при вводе; умные уведомления |
| 4 | AppAction, ActionRegistry, ActionResolver, Executor, уровни риска, ActionProposal, Undo, AppContext, навигация/тема/фильтр/сортировка/настройки — общие для чата и голоса |
| 5 | ML: признаки, версии, изолят, переобучение и метрики |
| 6 | Контекст разговора, голосовой помощник → движки, реакции Финоры, приоритет блоков главной, интерфейс AiProvider (выключен) |
| 7 | Smart search из чата, AI-теги, отчёты и digest, what-if, адаптеры импорта |
| 8 | Изоляты, инкрементальный пересчёт, 100 000+ операций, edge cases |

## 14. Phase 1 — сделано (1.0.0+138)

Существующие классы расширены, параллельных систем не создано.

- **Insight:** confidence, severity, `trace` (`InsightTrace`: движок,
  причина, входной период, связанные операции, `calculationVersion`,
  время), `dedupKey`, `id`, `relevance`. `InsightEngine.rank` отбрасывает
  слабые (< 0,4) и отложенные, оставляет один инсайт на факт и предмет и
  сортирует по релевантности. `snapshot.top` — до трёх самых полезных.
- **Cooldown:** `PersonalMemory.snooze / isSnoozed`, сохраняется в JSON.
- **Сравнение периодов:** `MonthComparisonEngine.comparePeriods` — день,
  неделя (с учётом начала недели), месяц (с учётом дня начала месяца),
  квартал, год, свой диапазон. Равное число дней; расходы, доходы,
  cashflow, рост и снижение по категориям; «мало данных» вместо выдумки.
- **RecurringDetector:** ритмы 2 недели и квартал, регулярный доход
  (`kind: income`, никогда не подписка), `lastAmount` и `amountChanged`
  (подорожание подписки), `isLate` с допуском по ритму. История — два года.
- **AnomalyDetector:** база по тому же магазину при ≥ 4 платежах (иначе по
  категории), `basis` и `history` для объяснения; `frequency` — всплеск
  числа операций относительно своих же прошлых месяцев.
- **CashflowEngine.timeline:** события до конца периода (правила
  приложения и найденные регулярные платежи с их confidence), прогнозный
  баланс по дням, самый низкий день, список «обычно уже был».
- **ForecastEngine:** confidence (история + прогресс периода, ≤ 0,95).
- **Новые инсайты:** `latePayment` («Обычно платёж … к этому времени уже
  проходил» — без «забыли оплатить»), `frequency`.
- **Чат:** «Что ты умеешь?» → список возможностей из `AiCapabilities`;
  «Сравни эту неделю / квартал / год с прошлым» → сравнение периодов.
- **Настройки → Финора → «Finora AI»:** экран возможностей с примерами;
  нажатие открывает чат и задаёт вопрос.
- **Тесты:** `test/finora_ai_phase1_test.dart` (22),
  `test/finora_ai_help_test.dart`. Каждый пример из списка возможностей
  проверяется на распознавание.

## 15. Phase 2 — сделано (1.0.0+139)

- **Merchant intelligence** (`classification/merchant_intelligence.dart`):
  - Канонический ключ места. Известные бренды распознаются через каталоги
    («PYATEROCHKA #123», «X5 PYATEROCHKA» и «Пятерочка» → один магазин).
  - У неизвестных мест убираются юрлица, номера точек и пунктуация.
  - Профиль строится из истории: имя, варианты написания, обычная
    категория и её доля, типичная сумма и диапазон 10–90 %, частота в
    месяц, последний раз, последний счёт.
  - Подсказки при вводе. Всем AI-движкам ключ даёт `AiContext.merchantKey`.
- **TransactionClassifier**: источники personal_memory, exact_rule,
  statistical_rule, merchant_rule, ml_model, fallback. У каждого варианта
  есть `evidence` — на скольких операциях он основан. Старые ключи памяти
  по-прежнему читаются.
- **AiConfig**: пороги (применить ≥ 0,7, предложить ≥ 0,5, не уверена
  < 0,45) и решение apply / suggest / choose с учётом уровня автоматизации.
- **Объяснимость**: `ResponseLayer.explain` — «Последние 8 покупок в этом
  месте были отнесены к …», «Ты сам 3 раза выбирал …».
- **Редактор операции**:
  - Подсказки известных мест (имя · типичная сумма). Нажатие подставляет
    имя, обычную категорию, сумму (если пусто) и последний счёт.
  - Когда Финора не уверена, предлагает до трёх категорий. Ничего не
    подставляется без нажатия, кроме уверенной категории в режиме
    «Умно» или «Автоматически».
- **Настройки Finora AI** (Настройки → Финора):
  - Переключатели: AI, автокатегоризация, предлагать категории,
    персонализация, умные наблюдения.
  - Уровень автоматизации: только предлагать / умно / автоматически.
  - «Сбросить персонализацию» — HIGH RISK, с подтверждением. Операции не
    трогает.
  - Выключенная персонализация: память не используется и не пополняется.
- **PersonalMemory v2** (паузы инсайтов), `MemoryRepository.replace`.
  Память Финоры входит в полную JSON-копию (`aiMemory`) и восстанавливается
  вместе с ней.
- **Тесты**: `test/finora_ai_phase2_test.dart` (13),
  `test/ai_settings_ui_test.dart` (2).

## 16. Phase 3 — сделано (1.0.0+140)

- **Природа регулярного платежа** (`RecurringDetector.natureOf`): подписка,
  аренда, кредит, коммуналка, перевод или прочее. Подпиской считается
  только известный сервис или ровная ежемесячная сумма без признаков
  обязательства. Прекратившиеся платежи определяются отдельно (`stopped`).
- **FinancialHealthEngine** (`insights/financial_health_engine.dart`):
  - Прогноз мечты: взнос в месяц и в неделю, темп за 3 месяца, ожидаемая
    дата, отставание от плана.
  - Аналитика подписок: в месяц и в год, новые, подорожавшие,
    прекратившиеся.
  - Финансовая подушка: накопительные счета и вклады против обычного
    месяца трат и обязательных платежей.
  - Индекс стабильности Финоры 0–100 из четырёх объяснимых частей:
    доходы, денежный поток, подушка, доля обязательных платежей. Это не
    кредитный рейтинг.
- **BudgetRisk.safeDaily**: сколько можно тратить в день, чтобы уложиться.
- **Возвраты** (`RefundDetector`): по словам или по сумме не больше
  недавнего расхода в том же месте (60 дней). Возвраты не считаются
  доходом в аналитике AI.
- **Дубли** (`domain/duplicate_detector.dart`): при сохранении новой
  операции с той же суммой, счётом и местом в пределах суток Финора
  спрашивает, сохранять ли ещё одну. Ничего не удаляет.
- **Необычный месяц**: в «Анализе» вопрос «Учитывать как обычный?». Ответ
  «Нет» исключает месяц из истории прогнозов (`PersonalMemory.excludedMonths`,
  память v3).
- **Умные уведомления** (`SmartNotifications`): может не хватить денег до
  конца месяца, необычная трата, платёж «обычно уже был», подорожание
  подписки. Приоритет, не больше одного в день, один факт никогда
  дважды. Переключатель — в «Настройках Finora AI».
- **Чат**: «Какие ближайшие платежи?», «На сколько хватит подушки?»,
  «Насколько стабильны мои финансы?», расширенный ответ про подписки.
  В «Анализе» появились разделы: ближайшие платежи, подписки, подушка и
  стабильность, мечты, необычный месяц.
- **Окно Finora AI**:
  - по центру тихое «Чем могу помочь?»;
  - огненный фон плавно перетекает (неподвижен при «уменьшить движение»);
  - компактные подсказки;
  - активный выбор модели «FinAI 1.0»: шторка с моделью на устройстве,
    облачные модели не подключены.
- **Тесты**: `test/finora_ai_phase3_test.dart` (12).

## 17. Phase 5 — сделано (ML классификатора)

Основа — существующий классификатор (логистическая регрессия на
хэшированных признаках, `tool/finora_ai/`, `lib/features/finora_ai/inference/`).
Переписывать его не стал.

- **Признаки.** Сумма (логарифмические корзины), день недели, месяц и тип
  счёта уже были. Время суток не добавлено: в данных есть только дата,
  а придумывать синтетическую связь «час → категория» значит подделать метрику.
  - Проверены варианты на шести разбиениях с отложенными магазинами:
    первое слово, символьные 4-граммы, префиксы слов, без даты, сильнее L2,
    меньше эпох. Все в пределах разброса между разбиениями (±5–7 п.п.) или хуже.
  - Принят только признак «сумма × тип операции» (`ak:`). Он лучше на 6 из 6
    разбиений: accuracy +1,15 п.п., top-3 +2,05 п.п., macro-F1 +0,76 п.п.
  - Данные синтетические, суммы в них сгенерированы по классам. На реальных
    операциях эффект нужно перепроверить.
- **Версии.** В файле модели появились `schema_version` (2) и
  `preprocessing_version` (2), рядом с `version` (1.1.0).
  - Приложение считает признаки той версии, на которой обучена модель:
    поддерживаются 1 и 2.
  - Файл без версий читается как схема 1 с признаками 1.
  - Неизвестная схема или версия признаков → модель не загружается,
    классификатор работает на памяти, истории и каталоге.
  - Константа версии одна в `features.py` и `features.dart`, тест сверяет их.
- **Вне UI-потока.** Модель разбирается в фоновом изоляте
  (`LinearModel.parseInBackground`). Если изоляты недоступны — в основном
  потоке. Пакетная классификация — `LinearModel.predictMany` в изоляте.
  Одиночное предсказание остаётся синхронным: на сборочной машине 37 мкс.
  Замеры здесь: разбор 2,6 мс, предсказание 37 мкс, 5000 предсказаний в
  изоляте 138 мс. На телефоне не измерено.
- **Метрики.** `train.py` пишет в `metrics.json` основное разбиение и
  среднее/разброс по шести разбиениям (`cross_split`), источник данных и версии.
  Модель 1.1.0: accuracy 0,637 ± 0,052, top-3 0,758 ± 0,060,
  macro-F1 0,636 ± 0,037. Обучение детерминированное (~4 с, плюс ~25 с на
  шесть разбиений; `--quick` пропускает их).
- **Переобучение на реальных данных.** `tool/finora_ai/from_backup.py
  backup.json out.csv` превращает JSON-копию Finora в строки набора данных.
  - Берутся только проведённые доходы и расходы с получателем.
  - Класс категории определяется правилами самого приложения:
    `category_mapper.dart` разбирается из Dart, второй таблицы нет.
  - Работает локально. Файл содержит личные данные, его нельзя коммитить.
  - Дообучение: `python3 tool/finora_ai/train.py --extra out.csv`.
- **Паритет Python ↔ Dart.** Фикстуры пересозданы для модели 1.1.0 и
  записывают версию признаков.
- **Тесты.** `test/finora_ai_phase5_test.dart` (7): версии признаков и
  файла, отказ от неизвестных версий, чтение старого файла, изолят и пакет,
  скорость предсказания, записанные метрики.
