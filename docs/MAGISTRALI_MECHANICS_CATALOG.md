# FINORA: Магистрали — каталог игровых механик

Единый источник требований: каждая механика с постоянным ID, приоритетом,
реальным статусом (по исходному коду, а не по плану), этапом, зависимостями,
файлами, тестами и известными проблемами. ID не меняются при перестановке
этапов. Каталог обновляется в конце каждого этапа.

Статусы: NOT_STARTED — не начато; PARTIAL — частично; IN_PROGRESS — в работе;
READY_FOR_REVIEW — готово, ждёт проверки игроком; VERIFIED — проверено игроком
(этапы, которые игрок подтвердил: 1.68–1.83); BLOCKED — заблокировано.

Файлы домена — `lib/domain/magistrali/`, интерфейса —
`lib/presentation/screens/world/magistrali/`. Тесты — `test/magistrali_<имя>_test.dart`
(sim, orders, storage, dispatch, towns, horses, production, growth,
industry, cities, logistics, rail, water, megapolis, passengers, p1, s12, ui, ui_stage5, ui_rail).

Аудит: 1.77.0, обновлено в 1.78.0 (S7) и 1.79.0 (S8), 1.80.0 (S9 и доводка ЖД), 1.81.0 (S10 и графика), 1.82.0 (S11), 1.83.0 (доделка P1), 1.84.0 (S12); точка восстановления — тег `restore/magistrali-1.77.0-pre-s7`.

## Сводка

| Статус | Механик |
|---|---|
| VERIFIED | 133 |
| READY_FOR_REVIEW | 3 |
| PARTIAL | 24 |
| NOT_STARTED | 43 |
| Всего | 203 |

## A. Фундамент игры и безопасность

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| CORE-01 | Единое игровое время | P0 | VERIFIED | 1.68 | — | world.dart (`speed` 0/1/2/4), world_sim.dart (`step`, 40 тиков/день) | sim | — |
| CORE-02 | Независимость логики от FPS | P0 | VERIFIED | 1.68 | CORE-01 | mag_screen.dart (`advance`: накопитель, шаг 100 мс) | sim: «saving and loading continues exactly» | — |
| CORE-03 | Единый реестр ресурсов | P0 | VERIFIED | 1.72 | — | config.dart (`MagCargo`), economy_catalog.dart | towns: «chains are whole» | — |
| CORE-04 | Единая игровая экономика | P0 | VERIFIED | 1.74 | CORE-05 | world.dart (`_spend`, `_earn`, `_assetSale`) | production: «no money from moving cargo round» | — |
| CORE-05 | Система событий игры | P0 | VERIFIED | 1.74 | — | ledger.dart (записи с id), settlements.dart (история) | production: «journal: unique ids» | Неденежные события — только история поселений |
| CORE-06 | Версионирование сохранений | P0 | VERIFIED | 1.69 | — | world_save.dart (формат 6), magistrali_store.dart (world.vN.json) | orders, production | — |
| CORE-07 | Миграции сохранений | P0 | VERIFIED | 1.69 | CORE-06 | world_save.dart (`migrateMagSave` 1→6), world_load.dart | фикстуры v1, v2, v3, v5_map2 | — |
| CORE-08 | Детерминированные тестовые сценарии | P0 | VERIFIED | 1.68 | CORE-02 | весь домен — чистый Dart, seed карты | sim, все тесты логики | — |
| CORE-09 | Конфигурация игрового баланса | P0 | READY_FOR_REVIEW | 1.84 | — | config.dart (`startMoneyBig`, `contractReach`), settlements.dart, tech_nodes.dart, economy_catalog.dart | s12 | Баланс большой карты — 1.84 |
| CORE-10 | Лог ошибок симуляции | P1 | PARTIAL | 1.68 | — | world_load.dart (проверки целостности и баланса грузов) | sim: «broken files» | Нет журнала ошибок во время игры |

## B. Поселения и развитие городов

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| CITY-01 | Независимое состояние поселений | P0 | VERIFIED | 1.72 | CITY-03 | settlements.dart, world_settlements.dart | towns | — |
| CITY-02 | Десять уровней развития | P1 | VERIFIED | 1.81 | — | settlements.dart (уровни 8–10: сталь, детали, кирпич в нуждах и росте; мегапроекты) | towns, megapolis | — |
| CITY-03 | Многоклеточная территория | P0 | VERIFIED | 1.72 | — | settlements.dart (`cells`), map.dart | towns | — |
| CITY-04 | Автоматическое расширение | P1 | VERIFIED | 1.72 | CITY-03 | world_settlements.dart (`_growTown`), map.dart (`expandCells`) | towns, growth | — |
| CITY-05 | Защита инфраструктуры | P0 | VERIFIED | 1.72 | CITY-04 | world_settlements.dart (`_townLandFree`) | towns: «growth blocked by roads» | — |
| CITY-06 | Изменение застройки | P1 | PARTIAL | 1.72 | CITY-03 | mag_town_art.dart, mag_city_art.dart | — | Застройка меняется группами уровней; в 1.81 — плавная земля и дороги вокруг |
| CITY-07 | Население | P1 | PARTIAL | 1.72 | CITY-01 | world_settlements.dart (`_dayTowns`) | towns, growth | Спрос задан уровнем, а не числом жителей |
| CITY-08 | Потребности города | P1 | VERIFIED | 1.77 | CITY-02, CORE-03 | settlements.dart (`needs`, `marketGoods`), world_cities.dart | cities | — |
| CITY-09 | Контракты развития | P1 | VERIFIED | 1.75 | CITY-08 | world_settlements.dart (`_payDevelopment`) | growth | — |
| CITY-10 | Транспортная доступность | P1 | PARTIAL | 1.72 | ROAD-12 | world_settlements.dart, mag_development.dart («нет дороги») | growth | Учитывается только через реальные поставки |
| CITY-11 | Специализации поселений | P2 | VERIFIED | 1.77 | CITY-08 | world_cities.dart, settlements.dart (`favoured`) | cities | — |
| CITY-12 | Репутация в городе | P2 | PARTIAL | 1.72 | — | settlements.dart (`reputation`) | — | Растёт, но преимуществ не даёт |
| CITY-13 | Несколько точек разгрузки | P2 | NOT_STARTED | — | LOG, ROUTE | — | — | Сейчас разгрузка у любой клетки города |
| CITY-14 | История поселения | P2 | VERIFIED | 1.72 | — | settlements.dart (`history`) | towns | — |
| CITY-15 | Удовлетворённость населения | P3 | VERIFIED | 1.72 | CITY-07 | world_settlements.dart (`satisfaction`, `growAt`) | towns | — |
| CITY-16 | Динамическое появление спроса | P1 | VERIFIED | 1.75 | CITY-08, CONT-12 | settlements.dart (`opens`, `marketGoods`), world_settlements.dart | growth, industry, cities | — |

## C. Эпохи и технологический прогресс

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| TECH-01 | Независимый технологический прогресс компании | P1 | VERIFIED | 1.70 | — | tech.dart, world_tech.dart | storage | — |
| TECH-02 | Эпоха гужевого транспорта | P1 | VERIFIED | 1.73 | — | config.dart (cart, wagon), world.dart (`start`) | horses | — |
| TECH-03 | Паровая эпоха | P1 | VERIFIED | 1.79 | RAIL-01 | tech_nodes.dart (`steam`), world_rails.dart | rail | — |
| TECH-04 | Эпоха автомобилизации | P1 | VERIFIED | 1.73 | TECH-07 | tech_nodes.dart (`combustion`), config.dart (асфальт) | horses | — |
| TECH-05 | Современная логистика | P1 | PARTIAL | 1.71 | LOG-07 | tech_nodes.dart (диспетчерская), шоссе, магистраль, тягач | dispatch | Нет отдельной эпохи |
| TECH-06 | Транспорт будущего | P3 | NOT_STARTED | — | — | — | — | — |
| TECH-07 | Дерево исследований | P1 | VERIFIED | 1.70 | — | tech.dart, tech_nodes.dart (36 узлов) | storage: «tree integrity» | — |
| TECH-08 | Исследования через достижения | P2 | PARTIAL | 1.70 | META-02 | tech.dart (`deliveries`) | storage | Учитывается только число доставок |
| TECH-09 | Сохранение старой техники | P1 | VERIFIED | 1.73 | — | world_tech.dart (`motorUnlocked`) | horses | — |
| TECH-10 | Новые рецепты по эпохам | P1 | VERIFIED | 1.83 | PROD-13 | tech_nodes_recipes.dart (5 технологий), config.dart (`MagIndustrySpec.tech`), world_industry.dart | p1, industry | Старые сохранения получают рецепты, доступные их уровню |

## D. Дороги и инфраструктура

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| ROAD-01 | Строительство дорог | P1 | VERIFIED | 1.83 | — | world.dart (`planRoad`, `buildRoad`), mag_screen_input.dart (только касания: начало, конец, продолжение; перетаскивание двигает карту), mag_build_panel.dart | sim, ui, ui_stage5 | Режим стройки переделан в 1.83 |
| ROAD-02 | Грунтовые дороги | P1 | READY_FOR_REVIEW | 1.84 | — | config.dart (`MagRoad.dirt`), mag_network_art.dart (разметка всех покрытий: колеи, пунктир, края, полосы) | — | — |
| ROAD-03 | Улучшение покрытия | P1 | VERIFIED | 1.76 | ROAD-01 | world_roads.dart (`upgradePlan`), mag_road.dart | industry, ui_stage5 | — |
| ROAD-04 | Перекрёстки | P1 | READY_FOR_REVIEW | 1.84 | — | world.dart (граф клеток), world_entrances.dart (один въезд к предприятию), pathfinding.dart | s12, sim | Въезд переносится в окне дороги |
| ROAD-05 | Удаление и возврат части стоимости | P1 | VERIFIED | 1.83 | — | world_roads.dart (`removeRoad`, `demolishRefund`: 30%), world_rails.dart | p1, ui_rail | — |
| ROAD-06 | Мосты | P1 | VERIFIED | 1.82 | — | config.dart (река ×9), mag_network_art.dart (`paintBridge`: настил, перила, опоры; ж/д ферма) | passengers | — |
| ROAD-07 | Тоннели | P3 | VERIFIED | 1.82 | ROAD-01 | config.dart (холм ×7), mag_network_art.dart (порталы, гора над дорогой) | passengers | Тоннель — дорога или путь на клетке холма |
| ROAD-08 | Пропускная способность | P2 | NOT_STARTED | — | — | — | — | — |
| ROAD-09 | Дорожные заторы | P3 | NOT_STARTED | — | ROAD-08 | — | — | — |
| ROAD-10 | Подсветка загруженности | P2 | NOT_STARTED | — | ROAD-08 | — | — | — |
| ROAD-11 | Предварительная стоимость строительства | P1 | VERIFIED | 1.68 | — | mag_tools.dart (панель подтверждения), mag_road.dart | ui | — |
| ROAD-12 | Проверка доступности маршрута | P0 | VERIFIED | 1.68 | — | world.dart (`roadPath`, `connected`) | sim | — |

## E. Транспорт и управление автопарком

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| VEH-01 | Лошадь и повозка | P1 | VERIFIED | 1.73 | — | config.dart (`cart`) | horses | — |
| VEH-02 | Улучшенные повозки | P1 | VERIFIED | 1.73 | — | config.dart (`wagon`) | horses | — |
| VEH-03 | Ранние грузовики | P1 | VERIFIED | 1.68 | TECH-04 | config.dart (pickup, lorry) | sim, horses | — |
| VEH-04 | Современные грузовики | P1 | VERIFIED | 1.83 | TECH-05 | config_vehicles.dart (`semi`, `electric`), world_fleet.dart (`tech`) | p1 | — |
| VEH-05 | Специализированные кузова | P2 | NOT_STARTED | — | — | — | — | — |
| VEH-06 | Покупка и продажа | P1 | VERIFIED | 1.68 | — | world_fleet.dart | sim | — |
| VEH-07 | Прокачка транспорта | P1 | VERIFIED | 1.68 | — | world_fleet.dart (`upgrade`) | sim: «upgrades really change» | — |
| VEH-08 | Износ | P1 | VERIFIED | 1.68 | — | world_sim.dart (`wear`) | sim | — |
| VEH-09 | Ремонт и обслуживание | P2 | VERIFIED | 1.68 | VEH-08 | world_fleet.dart (`service`, автообслуживание) | sim | — |
| VEH-10 | Депо | P2 | PARTIAL | 1.68 | — | состояние «в гараже» | — | Нет постройки депо |
| VEH-11 | Массовое управление | P2 | NOT_STARTED | — | — | — | — | — |
| VEH-12 | Автозамена устаревшей техники | P2 | NOT_STARTED | — | — | — | — | — |
| VEH-13 | Визуальная модернизация | P2 | NOT_STARTED | — | VEH-07 | — | — | — |
| VEH-14 | Коллекционная историческая техника | P3 | NOT_STARTED | — | — | — | — | — |

## F. Маршруты и оптимизация перевозок

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| ROUTE-01 | Создание маршрутов | P1 | VERIFIED | 1.68 | ROAD-12 | world.dart (`createRoute`), mag_routes.dart | sim, ui | — |
| ROUTE-02 | Несколько остановок | P1 | VERIFIED | 1.68 | — | entities.dart (`MagRoute.stops`) | sim: «two-line network» | — |
| ROUTE-03 | Кольцевые маршруты | P1 | VERIFIED | 1.68 | — | world_sim.dart | sim | — |
| ROUTE-04 | Несколько машин на линии | P1 | VERIFIED | 1.68 | — | world_fleet.dart (`assign`) | — | — |
| ROUTE-05 | Настройки погрузки | P1 | NOT_STARTED | — | ROUTE-01 | — | — | Машина берёт любой груз, нужный следующей остановке |
| ROUTE-06 | Минимальная загрузка | P2 | PARTIAL | 1.68 | — | world_sim.dart (ждёт полной загрузки) | sim | Не настраивается |
| ROUTE-07 | Максимальное время ожидания | P1 | VERIFIED | 1.68 | — | config.dart (`partialWaitDays`) | sim | — |
| ROUTE-08 | Обратные грузовые рейсы | P1 | VERIFIED | 1.68 | — | world_sim.dart (`_loadable` на каждой остановке) | sim | — |
| ROUTE-09 | Приоритетные грузы | P2 | NOT_STARTED | — | ROUTE-05 | — | — | — |
| ROUTE-10 | Условные остановки | P3 | NOT_STARTED | — | — | — | — | — |
| ROUTE-11 | Статистика линии | P1 | VERIFIED | 1.78 | FIN-01 | entities.dart (`costs`, `cells`, `emptyCells`), mag_finance.dart | logistics | Нет времени круга |
| ROUTE-12 | Копирование маршрутов | P2 | NOT_STARTED | — | — | — | — | — |
| ROUTE-13 | Перерасчёт после изменения дорог | P0 | VERIFIED | 1.68 | ROAD-12 | world_sim.dart (`roadVersion`, `noRoad`) | sim: «a broken road stops the truck» | — |
| ROUTE-14 | Показатель порожнего пробега | P2 | VERIFIED | 1.78 | — | entities.dart (`emptyShare`), mag_finance.dart | logistics, industry | — |

## G. Ресурсы, добыча и производство

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| PROD-01 | Природные месторождения | P1 | VERIFIED | 1.68 | MAP-03 | map.dart (добыча у холмов, леса, реки) | sim, industry | Запасы месторождений не исчерпываются |
| PROD-02 | Фермы | P1 | VERIFIED | 1.68 | — | config.dart | sim | — |
| PROD-03 | Лесозаготовки | P1 | VERIFIED | 1.68 | — | config.dart | sim | — |
| PROD-04 | Каменоломни | P1 | VERIFIED | 1.74 | — | config.dart | production | — |
| PROD-05 | Лесопилки | P1 | VERIFIED | 1.74 | — | config.dart | production | — |
| PROD-06 | Мельницы и пекарни | P1 | VERIFIED | 1.74 | — | config.dart | production | — |
| PROD-07 | Шахты | P1 | VERIFIED | 1.76 | — | config.dart (рудник, угольная шахта) | industry | — |
| PROD-08 | Металлургия | P1 | VERIFIED | 1.76 | PROD-07 | config.dart (`steelMill`, `extra`) | industry | — |
| PROD-09 | Строительные материалы | P1 | VERIFIED | 1.76 | — | config.dart (кирпич, доски, камень) | industry | — |
| PROD-10 | Машиностроение | P2 | PARTIAL | 1.76 | PROD-08 | config.dart (`partsFactory`) | industry | Только детали |
| PROD-11 | Топливо и нефтепереработка | P2 | NOT_STARTED | — | — | economy_catalog.dart (только конфигурация) | — | — |
| PROD-12 | Электроника | P2 | NOT_STARTED | — | — | economy_catalog.dart (только конфигурация) | — | — |
| PROD-13 | Конфигурируемые рецепты | P0 | VERIFIED | 1.74 | — | config.dart (`converts`, `ratio`, `extra`) | production, industry | — |
| PROD-14 | Ограничение мощности | P1 | VERIFIED | 1.74 | — | world_sim.dart (`processPerDay`, `outputCap`) | production | — |
| PROD-15 | Потребление реального сырья | P0 | VERIFIED | 1.68 | — | world_sim.dart | production, industry | — |
| PROD-16 | Производственные простои | P1 | VERIFIED | 1.74 | PROD-15 | world_sim.dart | industry: «ore alone» | Простой не показан отдельно в интерфейсе |
| PROD-17 | Улучшение производства | P1 | VERIFIED | 1.74 | BIZ-02 | world_industry.dart (`upgradeIndustry`) | production | — |
| PROD-18 | Расширение складов предприятия | P1 | VERIFIED | 1.74 | PROD-17 | world_industry.dart (`storageFactor`) | production | — |
| PROD-19 | Визуальные стадии завода | P2 | NOT_STARTED | — | PROD-17 | mag_buildings.dart (только флажок владельца) | — | — |
| PROD-20 | Побочная продукция | P3 | NOT_STARTED | — | — | — | — | — |

## H. Владение предприятиями и рынки

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| BIZ-01 | Независимые предприятия | P1 | VERIFIED | 1.68 | — | map.dart | sim | — |
| BIZ-02 | Покупка предприятия | P1 | VERIFIED | 1.74 | — | world_industry.dart (`buyIndustry`) | production | — |
| BIZ-03 | Строительство производства | P1 | VERIFIED | 1.74 | — | world_industry.dart (`buildIndustry`) | production, industry | — |
| BIZ-04 | Продажа предприятия | P1 | VERIFIED | 1.74 | — | world_industry.dart (`sellIndustry`) | production | — |
| BIZ-05 | Улучшения оборудования | P1 | VERIFIED | 1.74 | — | world_industry.dart | production | — |
| BIZ-06 | Приоритеты производства | P2 | NOT_STARTED | — | — | — | — | Завод с двумя рецептами перерабатывает в порядке конфигурации |
| BIZ-07 | Внутренние поставки | P0 | VERIFIED | 1.74 | FIN-01 | world_sim.dart (`_deliver`: transfer) | production | — |
| BIZ-08 | Продажа независимым потребителям | P1 | VERIFIED | 1.74 | — | world_sim.dart (`goods_sale`) | production | — |
| BIZ-09 | Динамические цены | P2 | VERIFIED | 1.82 | — | world_cities.dart (`glutFactor`, затоваривание до −30% с затуханием), world_settlements.dart | passengers | — |
| BIZ-10 | Перепроизводство | P1 | VERIFIED | 1.74 | PROD-14 | world_sim.dart (склад продукции ограничивает выпуск) | production | — |
| BIZ-11 | Рыночный дефицит | P2 | VERIFIED | 1.82 | BIZ-09 | world_cities.dart (`deficitBonusOf`: +25% за кончившийся нужный товар) | passengers, ui_rail | — |
| BIZ-12 | Специализация регионов | P2 | PARTIAL | 1.77 | CITY-11 | world_cities.dart | cities | Специализация по городам, а не регионам |
| BIZ-13 | Аукционы предприятий | P3 | NOT_STARTED | — | — | — | — | — |
| BIZ-14 | Промышленные комплексы | P2 | NOT_STARTED | — | LOG-08 | — | — | — |

## I. Контракты и развитие экономики

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| CONT-01 | Простые транспортные контракты | P1 | VERIFIED | 1.68 | — | world_progress.dart | sim | — |
| CONT-02 | Срочные заказы | P1 | VERIFIED | 1.77 | CONT-01 | world_cities.dart (городские заказы со сроком) | cities | — |
| CONT-03 | Контракты развития поселений | P1 | VERIFIED | 1.75 | CITY-09 | world_settlements.dart | growth | — |
| CONT-04 | Производственные заказы | P1 | NOT_STARTED | — | PROD-13 | — | — | — |
| CONT-05 | Регулярное снабжение | P1 | NOT_STARTED | — | LOG-12 | — | — | Кладовая города — регулярный спрос, но не контракт |
| CONT-06 | Многоэтапные контракты | P2 | NOT_STARTED | — | — | — | — | — |
| CONT-07 | Региональные контракты | P2 | NOT_STARTED | — | — | — | — | — |
| CONT-08 | Контракты инфраструктуры | P1 | VERIFIED | 1.81 | CITY-02 | world_mega.dart (стройка города принимает материалы, награда по завершении) | megapolis | — |
| CONT-09 | Репутация заказчика | P2 | PARTIAL | 1.72 | CITY-12 | settlements.dart (`reputation`) | — | Не влияет на условия |
| CONT-10 | Субсидируемые маршруты | P2 | PARTIAL | 1.77 | — | world_cities.dart (спрос недели +30%) | cities | — |
| CONT-11 | Уникальные дорогие заказы | P2 | PARTIAL | 1.77 | — | world_cities.dart (городские заказы) | cities | Не уникальные, повторяются |
| CONT-12 | Проверка достижимости контракта | P0 | VERIFIED | 1.75 | CORE-03 | world_settlements.dart (`cargoAvailable`), world_progress.dart | growth, industry, cities | — |

## J. Склады и автоматическая логистика

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| LOG-01 | Реальная складская вместимость | P0 | VERIFIED | 1.70 | — | world_storage.dart, world_orders.dart (`roomOf`) | storage | — |
| LOG-02 | Входные и выходные склады | P1 | VERIFIED | 1.68 | — | map.dart (`input`, `stock`) | production | — |
| LOG-03 | Резервирование товаров | P0 | VERIFIED | 1.69 | — | orders.dart (`reservedOut`, `reservedIn`) | orders | — |
| LOG-04 | Минимальные и желаемые запасы | P1 | VERIFIED | 1.70 | — | world_storage.dart (`MagStockRule`) | storage | — |
| LOG-05 | Автоматические заявки | P1 | VERIFIED | 1.70 | LOG-04 | world_storage.dart (`_planLogistics`) | storage | — |
| LOG-06 | Автопоиск поставщика | P1 | VERIFIED | 1.70 | ROAD-12 | world_storage.dart (ближайший связанный поставщик) | storage | — |
| LOG-07 | Автоподбор транспорта | P1 | VERIFIED | 1.71 | — | world_dispatch.dart, dispatcher.dart | dispatch | — |
| LOG-08 | Логистические центры | P1 | VERIFIED | 1.78 | LOG-05, LOG-07 | world_centers.dart, mag_center.dart | logistics, ui_stage5 | — |
| LOG-09 | Прокачка центра | P1 | VERIFIED | 1.78 | LOG-08 | world_centers.dart (радиус и число заявок по уровню) | logistics | — |
| LOG-10 | Приоритеты доставки | P1 | VERIFIED | 1.69 | — | orders.dart (`priority`) | dispatch | — |
| LOG-11 | Автоснабжение производств | P1 | VERIFIED | 1.78 | LOG-08 | world_centers.dart (`shortages`), world_storage.dart | logistics, storage | — |
| LOG-12 | Автоснабжение городов | P1 | VERIFIED | 1.78 | LOG-08, CITY-08 | world_centers.dart (кладовая и рост) | logistics | — |
| LOG-13 | Автоэкспорт излишков | P2 | PARTIAL | 1.70 | — | world_storage.dart (режим «Распределение») | storage | Только со склада |
| LOG-14 | Перегрузочные терминалы | P2 | VERIFIED | 1.80 | RAIL-02, SEA-01, LOG-01 | склад со станцией или портом (world_rails.dart, world_water.dart, world_storage.dart) | water: «a train and a truck meet at a warehouse» | Терминал — склад, отдельной постройки нет |
| LOG-15 | Объединение заказов | P2 | NOT_STARTED | — | — | — | — | — |
| LOG-16 | Экономный режим диспетчера | P2 | VERIFIED | 1.71 | LOG-07 | dispatcher.dart | dispatch | — |
| LOG-17 | Быстрый режим диспетчера | P2 | VERIFIED | 1.71 | LOG-07 | dispatcher.dart | dispatch | — |
| LOG-18 | Карта логистических проблем | P2 | VERIFIED | 1.78 | FIN-11 | world_advice.dart (`problemPlaces`), mag_game.dart (красные метки) | logistics | Метки только у мест, не у дорог |

## K. Железные дороги и морской транспорт

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| RAIL-01 | Строительство железных дорог | P1 | VERIFIED | 1.79 | ROAD-12, TECH-03 | world_rails.dart (`planRail`, `buildRail`, `removeRail`), mag_screen_input.dart | rail, ui_rail | Снос без возврата денег |
| RAIL-02 | Железнодорожные станции | P1 | VERIFIED | 1.79 | RAIL-01 | world_rails.dart (`buildStation`, станция в 2 клетках от места), mag_rail_ui.dart | rail, ui_rail | — |
| RAIL-03 | Паровозы | P1 | VERIFIED | 1.79 | TECH-03 | config.dart (`steam`) | rail | — |
| RAIL-04 | Современные локомотивы | P1 | VERIFIED | 1.79 | RAIL-03 | config.dart (`diesel`), tech «Тепловозная тяга» | rail | — |
| RAIL-05 | Грузовые вагоны | P1 | VERIFIED | 1.79 | RAIL-03 | world_fleet.dart (`setWagons`, `capacityOf`) | rail, ui_rail | Вагоны одного типа |
| RAIL-06 | Сборка поездов | P1 | VERIFIED | 1.79 | RAIL-05 | world_fleet.dart (локомотив + 1…N вагонов, замедление за вагон) | rail | — |
| RAIL-07 | Безопасное движение по путям | P1 | VERIFIED | 1.79 | RAIL-01 | world_rails.dart (`_trackClear`: ожидание, обход, уступить путь) | rail: «never meet in a cell», «give way» | На одной колее без разъездов поезда уступают, но работают плохо |
| RAIL-08 | Разъезды и сигналы | P2 | VERIFIED | 1.80 | RAIL-07 | world_rails.dart (`_departure`: станция — сигнал; `_oncoming`; обход по второму пути и перрону) | rail: «double track», «give way» | Нет отдельных светофоров и разъездов без станции |
| RAIL-09 | Модернизация поездов | P1 | VERIFIED | 1.79 | RAIL-03 | world_fleet.dart (общие линии улучшений) | rail | — |
| SEA-01 | Порты | P1 | VERIFIED | 1.80 | общие грузы, маршруты | world_water.dart (`buildPort`), mag_rail_ui.dart | water, ui_rail | — |
| SEA-02 | Баржи | P1 | VERIFIED | 1.80 | SEA-01 | config_vehicles.dart (`barge`) | water | — |
| SEA-03 | Грузовые корабли | P1 | VERIFIED | 1.80 | SEA-01 | config_vehicles.dart (`freighter`), tech «Судоверфь» | water | — |
| SEA-04 | Морские маршруты | P1 | VERIFIED | 1.80 | SEA-01 | world_water.dart (`waterPath`, диагональные шаги по реке) | water | Моря на карте нет: реки и озёра |
| SEA-05 | Модернизация судов | P2 | NOT_STARTED | — | SEA-02 | — | — | — |
| SEA-06 | Мультимодальные терминалы | P2 | PARTIAL | 1.80 | SEA-01, RAIL-02 | склад со станцией и портом | water | Через склад |

## L. Пассажирские перевозки

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| PASS-01 | Пассажирский спрос | P2 | VERIFIED | 1.82 | CITY-07, ROUTE-01 | world_settlements.dart (жители из населения, только при остановке), map.dart | passengers | — |
| PASS-02 | Конные экипажи | P2 | VERIFIED | 1.82 | PASS-01 | config_vehicles.dart (`coach`) | passengers | — |
| PASS-03 | Автобусы | P2 | VERIFIED | 1.82 | PASS-01, TECH-04 | config_vehicles.dart (`bus`), world_fleet.dart (`canCarry`) | passengers, ui_rail | — |
| PASS-04 | Пассажирские поезда | P2 | VERIFIED | 1.82 | PASS-01, RAIL-06 | world_fleet.dart (`canCarry`: поезда и суда возят людей) | passengers | Отдельных пассажирских вагонов нет |
| PASS-05 | Перевозка работников | P2 | NOT_STARTED | — | население, маршруты | — | — | — |
| PASS-06 | Пересадки | P3 | NOT_STARTED | — | население, маршруты | — | — | — |
| PASS-07 | Комфорт и время ожидания | P3 | NOT_STARTED | — | население, маршруты | — | — | — |
| PASS-08 | Трамваи | P3 | NOT_STARTED | — | население, маршруты | — | — | — |

## M. Финансы и управление компанией

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| FIN-01 | Единый журнал операций | P0 | VERIFIED | 1.74 | — | ledger.dart | production | — |
| FIN-02 | Доходы и расходы | P1 | VERIFIED | 1.68 | FIN-01 | entities.dart (`MagMonth`), world_finance.dart | production, industry | — |
| FIN-03 | Прибыльность транспорта | P1 | VERIFIED | 1.76 | FIN-01 | entities.dart (`costs`), world_finance.dart | industry | — |
| FIN-04 | Прибыльность маршрутов | P1 | VERIFIED | 1.78 | ROUTE-11 | entities.dart (`MagRoute.profit`), mag_finance.dart | logistics | — |
| FIN-05 | Прибыльность предприятий | P1 | VERIFIED | 1.74 | BIZ-02 | map.dart (`revenue`, `costs`), world_finance.dart | production, industry | — |
| FIN-06 | Себестоимость продукции | P1 | PARTIAL | 1.74 | FIN-05 | world_sim.dart (закупка, переработка, содержание) | production | Нет себестоимости единицы |
| FIN-07 | Стоимость активов | P1 | VERIFIED | 1.76 | — | world_finance.dart | industry | Склады не входят в стоимость компании |
| FIN-08 | Финансовый центр | P1 | VERIFIED | 1.76 | FIN-01 | mag_finance.dart | ui_stage5 | — |
| FIN-09 | Исторические графики | P1 | VERIFIED | 1.76 | FIN-02 | mag_finance.dart (12 месяцев) | — | — |
| FIN-10 | Региональная статистика | P2 | PARTIAL | 1.76 | — | mag_finance.dart (вкладка «Поселения») | industry | По поселениям, без регионов |
| FIN-11 | Анализ убыточности | P2 | VERIFIED | 1.78 | FIN-05 | world_advice.dart (убыток с причиной) | logistics | — |
| FIN-12 | Финансовые рекомендации | P2 | VERIFIED | 1.78 | FIN-11 | world_advice.dart, mag_advice.dart (вкладка «Советы») | logistics, ui_stage5 | — |
| FIN-13 | Оценка окупаемости | P2 | VERIFIED | 1.76 | FIN-05 | world_finance.dart (`paybackDays`) | industry | — |
| FIN-14 | Инвестиционное планирование | P3 | NOT_STARTED | — | FIN-13 | — | — | — |
| FIN-15 | Кредиты и проценты | P3 | NOT_STARTED | — | — | — | — | — |
| FIN-16 | Мягкий финансовый кризис | P2 | PARTIAL | 1.68 | — | баланс может уйти в минус (красный), активы можно продать | — | Нет явного восстановления |

## N. Карта и развитие игрового мира

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| MAP-01 | Процедурная генерация | P1 | VERIFIED | 1.83 | — | map.dart (генератор 5: карта 112×112, втрое больше) | p1, sim | Генераторы 1–4 не изменились |
| MAP-02 | Seed мира | P1 | VERIFIED | 1.68 | — | map.dart, world_save.dart | sim | — |
| MAP-03 | Распределение ресурсов | P1 | VERIFIED | 1.68 | — | map.dart (план предприятий, `near`) | industry | — |
| MAP-04 | Проверка жизнеспособности карты | P0 | PARTIAL | 1.68 | — | map.dart (гарантированная первая линия) | sim: «start line is possible» | Цепочки этапов 3–5 не проверяются на каждой карте |
| MAP-05 | Реки и озёра | P1 | VERIFIED | 1.83 | — | map.dart, map_noise.dart (`_carveBigRiver`: большая река делит карту) | p1, sim | — |
| MAP-06 | Леса и поля | P1 | VERIFIED | 1.68 | — | map.dart | sim | — |
| MAP-07 | Горные регионы | P2 | PARTIAL | 1.68 | — | map.dart (холмы) | — | Холмы без отдельных регионов |
| MAP-08 | Открытие новых регионов | P2 | NOT_STARTED | — | — | — | — | — |
| MAP-09 | Разнообразные биомы | P2 | PARTIAL | 1.84 | — | mag_terrain_art.dart (плавные переходы, берега, скалы, лес), mag_sea_art.dart (море с островами за краем карты) | — | Набор местности прежний |
| MAP-10 | Редкие месторождения | P2 | NOT_STARTED | — | — | — | — | — |
| MAP-11 | Редактор карты | P3 | NOT_STARTED | — | — | — | — | — |
| MAP-12 | Режим песочницы | P3 | NOT_STARTED | — | — | — | — | — |

## O. Долгосрочный прогресс и особые события

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| META-01 | Уровень компании | P1 | VERIFIED | 1.68 | — | world_progress.dart | sim | — |
| META-02 | Достижения | P1 | PARTIAL | 1.68 | — | world_progress.dart (задания, награды Мира Финоры) | sim | Нет раздела достижений |
| META-03 | Первый мегаполис | P1 | VERIFIED | 1.81 | CITY-02 | world_mega.dart (`_megapolisReached`, только поселение-хутор), settlements.dart (`origin`) | megapolis | — |
| META-04 | Постоянная отметка первого мегаполиса | P1 | VERIFIED | 1.81 | META-03 | world_save.dart (`megapolis`), mag_game.dart (золотая корона), награда Мира Финоры | megapolis, ui_rail | Отметка живёт в сохранении партии; новая компания начинает заново (награда в Мире Финоры остаётся) |
| META-05 | История транспортной империи | P2 | PARTIAL | 1.74 | — | ledger.dart, история поселений | — | Нет общей летописи |
| META-06 | Мегапроекты | P1 | VERIFIED | 1.81 | CONT-08 | megaprojects.dart, world_mega.dart, mag_mega_ui.dart, mag_mega_art.dart | megapolis, ui_rail | — |
| META-07 | Уникальные исторические контракты | P2 | NOT_STARTED | — | — | — | — | — |
| META-08 | Коллекция исторической техники | P3 | NOT_STARTED | — | — | — | — | — |
| META-09 | Конкурирующие компании | P3 | NOT_STARTED | — | — | — | — | — |
| META-10 | Поглощения компаний | P3 | NOT_STARTED | — | META-09 | — | — | — |
| META-11 | Различные сценарии старта | P2 | NOT_STARTED | — | — | — | — | — |
| META-12 | Развитие после 10-го уровня | P3 | NOT_STARTED | — | META-03 | — | — | — |
