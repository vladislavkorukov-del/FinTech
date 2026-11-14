# FINORA: Магистрали — каталог игровых механик

Единый источник требований: каждая механика с постоянным ID, приоритетом,
реальным статусом (по исходному коду, а не по плану), этапом, зависимостями,
файлами, тестами и известными проблемами. ID не меняются при перестановке
этапов. Каталог обновляется в конце каждого этапа.

Статусы: NOT_STARTED — не начато; PARTIAL — частично; IN_PROGRESS — в работе;
READY_FOR_REVIEW — готово, ждёт проверки игроком; VERIFIED — проверено игроком
(этапы, которые игрок подтвердил: 1.68–1.91); BLOCKED — заблокировано.

Файлы домена — `lib/domain/magistrali/`, интерфейса —
`lib/presentation/screens/world/magistrali/`. Тесты — `test/magistrali_<имя>_test.dart`
(sim, orders, storage, dispatch, towns, horses, production, growth,
industry, cities, logistics, rail, water, megapolis, passengers, p1, s12, s13, s14, s15, s16, s17, s18, s19, s20, soak, ui, ui_s17, ui_s15, ui_s13, ui_stage5, ui_rail).

Аудит: 1.77.0, обновлено в 1.78.0 (S7) и 1.79.0 (S8), 1.80.0 (S9 и доводка ЖД), 1.81.0 (S10 и графика), 1.82.0 (S11), 1.83.0 (доделка P1), 1.84.0 (S12), 1.85.0 (S13), 1.86.0 (S14), 1.87.0 (S15), 1.88.0 (S16), 1.89.0 (S17), 1.90.0 (S18), 1.91.0 (S19), 1.92.0 (S20); точка восстановления — тег `restore/magistrali-1.77.0-pre-s7`.

## Сводка

| Статус | Механик |
|---|---|
| VERIFIED | 185 |
| READY_FOR_REVIEW | 14 |
| PARTIAL | 4 |
| NOT_STARTED | 0 |
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
| CORE-09 | Конфигурация игрового баланса | P0 | VERIFIED | 1.84 | — | config.dart (`startMoneyBig`, `contractReach`), settlements.dart, tech_nodes.dart, economy_catalog.dart | s12 | Баланс большой карты — 1.84 |
| CORE-10 | Лог ошибок симуляции | P1 | READY_FOR_REVIEW | 1.92 | — | world_finish.dart (`simErrors`, `_safely`: ошибка машины останавливает только её; `_checkLedger`: учёт грузов исправляется ежедневно), mag_finish_ui.dart («Карта, регионы и журнал») | s20, soak, ui_s15 | — |

## B. Поселения и развитие городов

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| CITY-01 | Независимое состояние поселений | P0 | VERIFIED | 1.72 | CITY-03 | settlements.dart, world_settlements.dart | towns | — |
| CITY-02 | Десять уровней развития | P1 | VERIFIED | 1.81 | — | settlements.dart (уровни 8–10: сталь, детали, кирпич в нуждах и росте; мегапроекты) | towns, megapolis | — |
| CITY-03 | Многоклеточная территория | P0 | VERIFIED | 1.72 | — | settlements.dart (`cells`), map.dart | towns | — |
| CITY-04 | Автоматическое расширение | P1 | VERIFIED | 1.72 | CITY-03 | world_settlements.dart (`_growTown`), map.dart (`expandCells`) | towns, growth | — |
| CITY-05 | Защита инфраструктуры | P0 | VERIFIED | 1.72 | CITY-04 | world_settlements.dart (`_townLandFree`) | towns: «growth blocked by roads» | — |
| CITY-06 | Изменение застройки | P1 | READY_FOR_REVIEW | 1.92 | CITY-03 | mag_town_levels.dart (своя деталь застройки и центра на каждом из 10 уровней), mag_town_art.dart, mag_city_art.dart | — | — |
| CITY-07 | Население | P1 | READY_FOR_REVIEW | 1.92 | CITY-01 | world_finish.dart (`populationFactor`: ежедневные нужды растут с населением до ×1,5), world_settlements.dart | s20, towns, growth | — |
| CITY-08 | Потребности города | P1 | VERIFIED | 1.77 | CITY-02, CORE-03 | settlements.dart (`needs`, `marketGoods`), world_cities.dart | cities | — |
| CITY-09 | Контракты развития | P1 | VERIFIED | 1.75 | CITY-08 | world_settlements.dart (`_payDevelopment`; 1.92: рост — одна шкала `growthProgress`, без порога населения) | growth | — |
| CITY-10 | Транспортная доступность | P1 | READY_FOR_REVIEW | 1.92 | ROAD-12 | world_finish.dart (`accessModes`, `accessFactor`: +25% к притоку жителей за каждый вид транспорта сверх первого), mag_finish_ui.dart | s20, ui_s15 | — |
| CITY-11 | Специализации поселений | P2 | VERIFIED | 1.77 | CITY-08 | world_cities.dart, settlements.dart (`favoured`) | cities | — |
| CITY-12 | Репутация в городе | P2 | VERIFIED | 1.91 | — | settlements.dart (`reputation`), world_rivals.dart (`reputationBonus`: до +10% к рынку), mag_city.dart | s19 | — |
| CITY-13 | Несколько точек разгрузки | P2 | VERIFIED | 1.89 | LOG, ROUTE | world_complex.dart (терминалы: `buildTerminal`, +5% к оплате, до 1 + уровень/3), mag_road.dart, mag_structures_art.dart | s17, ui_s17 | — |
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
| TECH-05 | Современная логистика | P1 | READY_FOR_REVIEW | 1.92 | LOG-07 | world_finish.dart (`eraName`: эпохи I–V, IV — диспетчерская и шоссе), mag_fleet.dart | s20 | — |
| TECH-06 | Транспорт будущего | P3 | VERIFIED | 1.91 | TECH-01 | tech_nodes_recipes.dart (`autopilot`, `maglev`), config_vehicles.dart (беспилотник 22 ур., маглев 25 ур.) | s19 | — |
| TECH-07 | Дерево исследований | P1 | VERIFIED | 1.70 | — | tech.dart, tech_nodes.dart (36 узлов) | storage: «tree integrity» | — |
| TECH-08 | Исследования через достижения | P2 | VERIFIED | 1.91 | META-02 | world_rivals.dart (`techCost`: −1% за достижение, до −20%), mag_tech.dart | s19 | — |
| TECH-09 | Сохранение старой техники | P1 | VERIFIED | 1.73 | — | world_tech.dart (`motorUnlocked`) | horses | — |
| TECH-10 | Новые рецепты по эпохам | P1 | VERIFIED | 1.83 | PROD-13 | tech_nodes_recipes.dart (5 технологий), config.dart (`MagIndustrySpec.tech`), world_industry.dart | p1, industry | Старые сохранения получают рецепты, доступные их уровню |

## D. Дороги и инфраструктура

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| ROAD-01 | Строительство дорог | P1 | VERIFIED | 1.83 | — | world.dart (`planRoad`, `buildRoad`), mag_screen_input.dart (только касания: начало, конец, продолжение; перетаскивание двигает карту), mag_build_panel.dart | sim, ui, ui_stage5 | Режим стройки переделан в 1.83 |
| ROAD-02 | Грунтовые дороги | P1 | VERIFIED | 1.84 | — | config.dart (`MagRoad.dirt`), mag_network_art.dart (разметка всех покрытий: колеи, пунктир, края, полосы) | — | — |
| ROAD-03 | Улучшение покрытия | P1 | VERIFIED | 1.76 | ROAD-01 | world_roads.dart (`upgradePlan`), mag_road.dart | industry, ui_stage5 | — |
| ROAD-04 | Перекрёстки | P1 | VERIFIED | 1.84 | — | world.dart (граф клеток), world_entrances.dart (один въезд к предприятию), pathfinding.dart | s12, sim | Въезд переносится в окне дороги |
| ROAD-05 | Удаление и возврат части стоимости | P1 | VERIFIED | 1.83 | — | world_roads.dart (`removeRoad`, `demolishRefund`: 30%), world_rails.dart | p1, ui_rail | — |
| ROAD-06 | Мосты | P1 | VERIFIED | 1.82 | — | config.dart (река ×9), mag_network_art.dart (`paintBridge`: настил, перила, опоры; ж/д ферма) | passengers | — |
| ROAD-07 | Тоннели | P3 | VERIFIED | 1.82 | ROAD-01 | config.dart (холм ×7), mag_network_art.dart (порталы, гора над дорогой) | passengers | Тоннель — дорога или путь на клетке холма |
| ROAD-08 | Пропускная способность | P2 | VERIFIED | 1.85 | — | config.dart (`MagRoadSpec.capacity`: 24/48/96/192 машин в день), world_routes.dart (`trafficOf`, `loadOf`, `congestionOf`), world_sim.dart | s13 | — |
| ROAD-09 | Дорожные заторы | P3 | READY_FOR_REVIEW | 1.92 | ROAD-08 | world_routes.dart (`congestionOf`), world_finish.dart (`jams`), world_advice.dart (совет «Пробки») | s13, s20 | — |
| ROAD-10 | Подсветка загруженности | P2 | VERIFIED | 1.85 | ROAD-08 | mag_network_art.dart (`paintTraffic`), mag_build_panel.dart («Загруженность»), mag_road.dart | s13, ui_s13 | — |
| ROAD-11 | Предварительная стоимость строительства | P1 | VERIFIED | 1.68 | — | mag_tools.dart (панель подтверждения), mag_road.dart | ui | — |
| ROAD-12 | Проверка доступности маршрута | P0 | VERIFIED | 1.68 | — | world.dart (`roadPath`, `connected`) | sim | — |

## E. Транспорт и управление автопарком

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| VEH-01 | Лошадь и повозка | P1 | VERIFIED | 1.73 | — | config.dart (`cart`) | horses | — |
| VEH-02 | Улучшенные повозки | P1 | VERIFIED | 1.73 | — | config.dart (`wagon`) | horses | — |
| VEH-03 | Ранние грузовики | P1 | VERIFIED | 1.68 | TECH-04 | config.dart (pickup, lorry) | sim, horses | — |
| VEH-04 | Современные грузовики | P1 | VERIFIED | 1.83 | TECH-05 | config_vehicles.dart (`semi`, `electric`), world_fleet.dart (`tech`) | p1 | — |
| VEH-05 | Специализированные кузова | P2 | VERIFIED | 1.89 | — | config_vehicles.dart (цистерна, рефрижератор, самосвал; `body`), world_complex.dart (`_bodyAllows`, `cargoPayFactor`) | s17, ui_s17 | — |
| VEH-06 | Покупка и продажа | P1 | VERIFIED | 1.68 | — | world_fleet.dart | sim | — |
| VEH-07 | Прокачка транспорта | P1 | VERIFIED | 1.68 | — | world_fleet.dart (`upgrade`) | sim: «upgrades really change» | — |
| VEH-08 | Износ | P1 | VERIFIED | 1.68 | — | world_sim.dart (`wear`) | sim | — |
| VEH-09 | Ремонт и обслуживание | P2 | VERIFIED | 1.68 | VEH-08 | world_fleet.dart (`service`, автообслуживание) | sim | — |
| VEH-10 | Депо | P2 | VERIFIED | 1.88 | — | world_works.dart (`buildDepot`, `_atDepot`, `depotUpkeep`), mag_road.dart, mag_structures_art.dart (`paintDepot`) | s16, ui_s15 | — |
| VEH-11 | Массовое управление | P2 | VERIFIED | 1.87 | — | world_meta.dart (`repairAll`, `assignIdle`), mag_fleet_bulk.dart | s15, ui_s15 | — |
| VEH-12 | Автозамена устаревшей техники | P2 | VERIFIED | 1.87 | — | world_meta.dart (`newerModelFor`, `replaceVehicle`, `replaceAllOutdated`), mag_fleet_bulk.dart, mag_fleet.dart | s15, ui_s15 | Замена по кнопке, не сама |
| VEH-13 | Визуальная модернизация | P2 | VERIFIED | 1.90 | VEH-07 | world_network.dart (`paintVehicle`, `visualTier`), mag_art.dart (покраска, золотые нашивки), mag_fleet_bulk.dart | s18, ui_s17 | — |
| VEH-14 | Коллекционная историческая техника | P3 | VERIFIED | 1.91 | META-08 | config_vehicles.dart (`veteran`, кузов `retro`, +10% к оплате), world_fleet.dart (открывается при 8 моделях) | s19 | — |

## F. Маршруты и оптимизация перевозок

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| ROUTE-01 | Создание маршрутов | P1 | VERIFIED | 1.84 | ROAD-12 | world.dart (`createRoute`), mag_routes.dart, mag_route_map.dart (1.91: основной способ — касания по объектам на карте, стрелки к получателям), mag_route_create.dart (поиск, группы, предложения по грузу) | sim, ui, ui_s17, ui_rail | — |
| ROUTE-02 | Несколько остановок | P1 | VERIFIED | 1.85 | — | entities.dart (`MagRoute.stops`), mag_stop_orders.dart (`routeSteps`: план по шагам) | sim, s13 | Длинные цепочки: забрал — переработка — забрал готовое — в город |
| ROUTE-03 | Кольцевые маршруты | P1 | VERIFIED | 1.68 | — | world_sim.dart | sim | — |
| ROUTE-04 | Несколько машин на линии | P1 | VERIFIED | 1.68 | — | world_fleet.dart (`assign`) | — | — |
| ROUTE-05 | Настройки погрузки | P1 | VERIFIED | 1.85 | ROUTE-01 | entities.dart (`pickAt`, `noPick`, `noDrop`), world_routes.dart (`setStopOrder`, `_loadable`), mag_stop_orders.dart | s13, ui_s13 | — |
| ROUTE-06 | Минимальная загрузка | P2 | VERIFIED | 1.87 | — | entities.dart (`minLoad`), world_routes.dart (`setMinLoad`), world_sim.dart, mag_routes.dart | s15, ui_s15 | 100/75/50/25/0% |
| ROUTE-07 | Максимальное время ожидания | P1 | VERIFIED | 1.68 | — | config.dart (`partialWaitDays`) | sim | — |
| ROUTE-08 | Обратные грузовые рейсы | P1 | VERIFIED | 1.68 | — | world_sim.dart (`_loadable` на каждой остановке) | sim | — |
| ROUTE-09 | Приоритетные грузы | P2 | VERIFIED | 1.86 | ROUTE-05 | entities.dart (`priority`), world_plans.dart (`setPriority`, `_priorityPick`), mag_stop_orders.dart (`pickPriority`) | s14, ui_s13 | — |
| ROUTE-10 | Условные остановки | P3 | VERIFIED | 1.87 | — | entities.dart (`ifCargo`), world_routes.dart (`_nextStop`, `_needed`), mag_stop_orders.dart | s15, ui_s15 | — |
| ROUTE-11 | Статистика линии | P1 | VERIFIED | 1.78 | FIN-01 | entities.dart (`costs`, `cells`, `emptyCells`), mag_finance.dart | logistics | Нет времени круга |
| ROUTE-12 | Копирование маршрутов | P2 | VERIFIED | 1.86 | — | world_plans.dart (`copyRoute`: копия и обратный маршрут с указаниями и приоритетом), mag_routes.dart | s14, ui_s13 | — |
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
| PROD-11 | Топливо и нефтепереработка | P2 | VERIFIED | 1.89 | — | config.dart (`oil`, `fuel`), config_industries.dart (вышка, НПЗ), tech_nodes_recipes.dart («Нефтедобыча»), map.dart (генератор 6), mag_oil_art.dart | s17 | — |
| PROD-12 | Электроника | P2 | VERIFIED | 1.89 | — | config_industries.dart (завод электроники: детали + топливо), settlements.dart (рынок городов 7+) | s17 | Упрощённая цепочка |
| PROD-13 | Конфигурируемые рецепты | P0 | VERIFIED | 1.74 | — | config.dart (`converts`, `ratio`, `extra`) | production, industry | — |
| PROD-14 | Ограничение мощности | P1 | VERIFIED | 1.74 | — | world_sim.dart (`processPerDay`, `outputCap`) | production | — |
| PROD-15 | Потребление реального сырья | P0 | VERIFIED | 1.68 | — | world_sim.dart | production, industry | — |
| PROD-16 | Производственные простои | P1 | VERIFIED | 1.74 | PROD-15 | world_sim.dart | industry: «ore alone» | Простой не показан отдельно в интерфейсе |
| PROD-17 | Улучшение производства | P1 | VERIFIED | 1.74 | BIZ-02 | world_industry.dart (`upgradeIndustry`) | production | — |
| PROD-18 | Расширение складов предприятия | P1 | VERIFIED | 1.74 | PROD-17 | world_industry.dart (`storageFactor`) | production | — |
| PROD-19 | Визуальные стадии завода | P2 | VERIFIED | 1.90 | PROD-17 | mag_structures_art.dart (`paintLevelStages`: пристройки, бак, корпус, золотой знак) | — | — |
| PROD-20 | Побочная продукция | P3 | VERIFIED | 1.90 | — | config.dart (`byProducts`), world_network.dart (`_byProduct`): сталь и кирпич → щебень, НПЗ → кокс | s18 | — |

## H. Владение предприятиями и рынки

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| BIZ-01 | Независимые предприятия | P1 | VERIFIED | 1.68 | — | map.dart | sim | — |
| BIZ-02 | Покупка предприятия | P1 | VERIFIED | 1.74 | — | world_industry.dart (`buyIndustry`) | production | — |
| BIZ-03 | Строительство производства | P1 | VERIFIED | 1.74 | — | world_industry.dart (`buildIndustry`) | production, industry | — |
| BIZ-04 | Продажа предприятия | P1 | VERIFIED | 1.74 | — | world_industry.dart (`sellIndustry`) | production | — |
| BIZ-05 | Улучшения оборудования | P1 | VERIFIED | 1.74 | — | world_industry.dart | production | — |
| BIZ-06 | Приоритеты производства | P2 | VERIFIED | 1.88 | — | world_works.dart (`setFirstInput`, `_recipesOf`), mag_works_ui.dart | s16, ui_s15 | Для своих заводов с несколькими рецептами |
| BIZ-07 | Внутренние поставки | P0 | VERIFIED | 1.74 | FIN-01 | world_sim.dart (`_deliver`: transfer) | production | — |
| BIZ-08 | Продажа независимым потребителям | P1 | VERIFIED | 1.74 | — | world_sim.dart (`goods_sale`) | production | — |
| BIZ-09 | Динамические цены | P2 | VERIFIED | 1.82 | — | world_cities.dart (`glutFactor`, затоваривание до −30% с затуханием), world_settlements.dart | passengers | — |
| BIZ-10 | Перепроизводство | P1 | VERIFIED | 1.74 | PROD-14 | world_sim.dart (склад продукции ограничивает выпуск) | production | — |
| BIZ-11 | Рыночный дефицит | P2 | VERIFIED | 1.82 | BIZ-09 | world_cities.dart (`deficitBonusOf`: +25% за кончившийся нужный товар) | passengers, ui_rail | — |
| BIZ-12 | Специализация регионов | P2 | READY_FOR_REVIEW | 1.92 | CITY-11 | world_finish.dart (`regionSpecialization`, `regionFactor`: свои добытчики профиля региона +10%), mag_finish_ui.dart | s20 | — |
| BIZ-13 | Аукционы предприятий | P3 | VERIFIED | 1.90 | — | world_network.dart (`MagAuction`, `_dayAuction`, `buyAuction`), mag_works_ui.dart (вкладка «Инвестиции») | s18, ui_s17 | — |
| BIZ-14 | Промышленные комплексы | P2 | VERIFIED | 1.89 | LOG-08 | world_complex.dart (`complexPartner`: +15% и конвейер 20 ед./день) | s17 | Свои заводы в 5 клетках, связанные рецептом |

## I. Контракты и развитие экономики

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| CONT-01 | Простые транспортные контракты | P1 | VERIFIED | 1.68 | — | world_progress.dart | sim | — |
| CONT-02 | Срочные заказы | P1 | VERIFIED | 1.77 | CONT-01 | world_cities.dart (городские заказы со сроком) | cities | — |
| CONT-03 | Контракты развития поселений | P1 | VERIFIED | 1.75 | CITY-09 | world_settlements.dart | growth | — |
| CONT-04 | Производственные заказы | P1 | VERIFIED | 1.88 | PROD-13 | world_deals.dart (`MagDealKind.production`, `_countProduction`), mag_works_ui.dart | s16, ui_s15 | — |
| CONT-05 | Регулярное снабжение | P1 | VERIFIED | 1.88 | LOG-12 | world_deals.dart (`MagDealKind.supply`: 4 периода по 7 дней, оплата за период) | s16 | Сорванный период закрывает контракт без штрафа |
| CONT-06 | Многоэтапные контракты | P2 | VERIFIED | 1.88 | — | world_deals.dart (`MagDealKind.stages`: сырьё на переработку → продукт покупателю) | s16 | — |
| CONT-07 | Региональные контракты | P2 | VERIFIED | 1.88 | — | world_deals.dart (`MagDealKind.region`: любые поселения в 16 клетках) | s16 | — |
| CONT-08 | Контракты инфраструктуры | P1 | VERIFIED | 1.81 | CITY-02 | world_mega.dart (стройка города принимает материалы, награда по завершении) | megapolis | — |
| CONT-09 | Репутация заказчика | P2 | VERIFIED | 1.91 | CITY-12 | world_progress.dart (выплата контракта × репутация), world_rivals.dart | s19 | — |
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
| LOG-07 | Автоподбор транспорта | P1 | VERIFIED | 1.71 | — | world_dispatch.dart, dispatcher.dart; 1.92: ручное назначение делит большой заказ (`assignOrder` split) | dispatch | — |
| LOG-08 | Логистические центры | P1 | VERIFIED | 1.78 | LOG-05, LOG-07 | world_centers.dart, mag_center.dart | logistics, ui_stage5 | — |
| LOG-09 | Прокачка центра | P1 | VERIFIED | 1.78 | LOG-08 | world_centers.dart (радиус и число заявок по уровню) | logistics | — |
| LOG-10 | Приоритеты доставки | P1 | VERIFIED | 1.69 | — | orders.dart (`priority`) | dispatch | — |
| LOG-11 | Автоснабжение производств | P1 | VERIFIED | 1.78 | LOG-08 | world_centers.dart (`shortages`), world_storage.dart | logistics, storage | — |
| LOG-12 | Автоснабжение городов | P1 | VERIFIED | 1.78 | LOG-08, CITY-08 | world_centers.dart (кладовая и рост) | logistics | — |
| LOG-13 | Автоэкспорт излишков | P2 | READY_FOR_REVIEW | 1.92 | — | world_storage.dart (распределение склада), world_finish.dart (`autoExport`, `_dayExport`: свои предприятия продают сверх 80% склада за полцены) | s20 | — |
| LOG-14 | Перегрузочные терминалы | P2 | VERIFIED | 1.80 | RAIL-02, SEA-01, LOG-01 | склад со станцией или портом (world_rails.dart, world_water.dart, world_storage.dart) | water: «a train and a truck meet at a warehouse» | Терминал — склад, отдельной постройки нет |
| LOG-15 | Объединение заказов | P2 | VERIFIED | 1.88 | — | world_works.dart (`mergeOrders`, `autoMerge`), mag_orders.dart | s16, ui_s15 | — |
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
| SEA-05 | Модернизация судов | P2 | VERIFIED | 1.89 | SEA-02 | world_complex.dart (`upgradeHull`: +15% груза, 3 ступени), mag_fleet.dart | s17, ui_s17 | — |
| SEA-06 | Мультимодальные терминалы | P2 | READY_FOR_REVIEW | 1.92 | SEA-01, RAIL-02 | world_finish.dart (`isMultimodal`: склад со станцией и причалом +50% места), mag_warehouse.dart | s20 | — |

## L. Пассажирские перевозки

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| PASS-01 | Пассажирский спрос | P2 | VERIFIED | 1.82 | CITY-07, ROUTE-01 | world_settlements.dart (жители из населения, только при остановке), map.dart | passengers | — |
| PASS-02 | Конные экипажи | P2 | VERIFIED | 1.82 | PASS-01 | config_vehicles.dart (`coach`) | passengers | — |
| PASS-03 | Автобусы | P2 | VERIFIED | 1.82 | PASS-01, TECH-04 | config_vehicles.dart (`bus`), world_fleet.dart (`canCarry`) | passengers, ui_rail | — |
| PASS-04 | Пассажирские поезда | P2 | VERIFIED | 1.82 | PASS-01, RAIL-06 | world_fleet.dart (`canCarry`: поезда и суда возят людей) | passengers | Отдельных пассажирских вагонов нет |
| PASS-05 | Перевозка работников | P2 | VERIFIED | 1.85 | PASS-01 | config.dart (`MagCargo.workers`), world_settlements.dart, world_routes.dart (`_deliverWorkers`), world_industry.dart (`staffBonusOf`: до +30%) | s13, ui_s13 | — |
| PASS-06 | Пересадки | P3 | VERIFIED | 1.90 | население, маршруты | world_network.dart (`isHub`, `transferAt`: 30% пассажиров в узле едут дальше) | s18 | Узел — поселение двух маршрутов и больше |
| PASS-07 | Комфорт и время ожидания | P3 | VERIFIED | 1.89 | население, маршруты | config_vehicles.dart (`comfort`), world_complex.dart (`_peopleLeave`: 20% долго ждущих в день) | s17 | — |
| PASS-08 | Трамваи | P3 | VERIFIED | 1.90 | население, маршруты | config_vehicles.dart (`tram`), world_network.dart (`tramRouteBlocker`), технология «Электротранспорт» | s18 | — |

## M. Финансы и управление компанией

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| FIN-01 | Единый журнал операций | P0 | VERIFIED | 1.74 | — | ledger.dart | production | — |
| FIN-02 | Доходы и расходы | P1 | VERIFIED | 1.68 | FIN-01 | entities.dart (`MagMonth`), world_finance.dart | production, industry | — |
| FIN-03 | Прибыльность транспорта | P1 | VERIFIED | 1.76 | FIN-01 | entities.dart (`costs`), world_finance.dart | industry | — |
| FIN-04 | Прибыльность маршрутов | P1 | VERIFIED | 1.78 | ROUTE-11 | entities.dart (`MagRoute.profit`), mag_finance.dart | logistics | — |
| FIN-05 | Прибыльность предприятий | P1 | VERIFIED | 1.74 | BIZ-02 | map.dart (`revenue`, `costs`), world_finance.dart | production, industry | — |
| FIN-06 | Себестоимость продукции | P1 | READY_FOR_REVIEW | 1.92 | FIN-05 | world_finish.dart (`unitCost`), mag_finish_ui.dart (окно предприятия) | s20 | — |
| FIN-07 | Стоимость активов | P1 | VERIFIED | 1.76 | — | world_finance.dart | industry | Склады не входят в стоимость компании |
| FIN-08 | Финансовый центр | P1 | VERIFIED | 1.76 | FIN-01 | mag_finance.dart | ui_stage5 | — |
| FIN-09 | Исторические графики | P1 | VERIFIED | 1.76 | FIN-02 | mag_finance.dart (12 месяцев) | — | — |
| FIN-10 | Региональная статистика | P2 | READY_FOR_REVIEW | 1.92 | — | world_finish.dart (`regionStats`: 9 регионов — места, свои, выручка), mag_finish_ui.dart | s20, ui_s15 | — |
| FIN-11 | Анализ убыточности | P2 | VERIFIED | 1.78 | FIN-05 | world_advice.dart (убыток с причиной) | logistics | — |
| FIN-12 | Финансовые рекомендации | P2 | VERIFIED | 1.78 | FIN-11 | world_advice.dart, mag_advice.dart (вкладка «Советы») | logistics, ui_stage5 | — |
| FIN-13 | Оценка окупаемости | P2 | VERIFIED | 1.76 | FIN-05 | world_finance.dart (`paybackDays`) | industry | — |
| FIN-14 | Инвестиционное планирование | P3 | VERIFIED | 1.86 | FIN-13 | world_plans.dart (`investmentIdeas`: машина на маршрут, уровень предприятия, покупка, дорога в пробке), mag_invest.dart (вкладка «Инвестиции») | s14, ui_s13 | Оценка по фактической прибыли |
| FIN-15 | Кредиты и проценты | P3 | VERIFIED | 1.87 | — | world_meta.dart (`takeLoan`, `repayLoan`, `dailyInterest`), ledger.dart (`financing`), mag_loan.dart | s15, ui_s15 | — |
| FIN-16 | Мягкий финансовый кризис | P2 | VERIFIED | 1.91 | — | world_rivals.dart (`_dayCrisis`: овердрафт 1% в день, предупреждение на 30-й день), можно продать активы и взять кредит | s19 | — |

## N. Карта и развитие игрового мира

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| MAP-01 | Процедурная генерация | P1 | VERIFIED | 1.83 | — | map.dart (генератор 5: карта 112×112, втрое больше) | p1, sim | Генераторы 1–4 не изменились |
| MAP-02 | Seed мира | P1 | VERIFIED | 1.68 | — | map.dart, world_save.dart | sim | — |
| MAP-03 | Распределение ресурсов | P1 | VERIFIED | 1.68 | — | map.dart (план предприятий, `near`) | industry | — |
| MAP-04 | Проверка жизнеспособности карты | P0 | READY_FOR_REVIEW | 1.92 | — | map.dart (гарантированная первая линия), world_finish.dart (`chainReport`, `mapViable`: у каждого сырья цепочки есть поставщик в 70 клетках) | sim, s20, ui_s15 | — |
| MAP-05 | Реки и озёра | P1 | VERIFIED | 1.83 | — | map.dart, map_noise.dart (`_carveBigRiver`: большая река делит карту) | p1, sim | — |
| MAP-06 | Леса и поля | P1 | VERIFIED | 1.68 | — | map.dart | sim | — |
| MAP-07 | Горные регионы | P2 | READY_FOR_REVIEW | 1.92 | — | world_finish.dart (`mountains`: хребты от 25 клеток холмов с именами, `mountainFactor`: добыча +20%), mag_decor_cache.dart (названия на карте) | s20 | — |
| MAP-08 | Открытие новых регионов | P2 | VERIFIED | 1.90 | — | world_network.dart (`regionOf`, `openRegion`, 3×3 региона), mag_structures_art.dart, mag_works_ui.dart | s18, ui_s17 | Только в новых компаниях |
| MAP-09 | Разнообразные биомы | P2 | PARTIAL | 1.84 | — | mag_terrain_art.dart (плавные переходы, берега, скалы, лес), mag_sea_art.dart (море с островами за краем карты) | — | Набор местности прежний |
| MAP-10 | Редкие месторождения | P2 | VERIFIED | 1.88 | — | world_works.dart (`isRich`: каждый 6-й добытчик, +50%), mag_structures_art.dart (`paintGem`), mag_works_ui.dart | s16, ui_s15 | Определяются зерном карты |
| MAP-11 | Редактор карты | P3 | READY_FOR_REVIEW | 1.92 | MAP-12 | map.dart (`setTerrain`), world_finish.dart (`editTerrain`, `terrainEdits` в сохранении), mag_build_panel.dart (вкладка «Карта» в песочнице: луг, лес, горы, озеро) | s20 | Только местность; предприятия ставятся обычной стройкой |
| MAP-12 | Режим песочницы | P3 | VERIFIED | 1.91 | — | world_complex.dart (`MagScenario.sandbox`: 10 000 000 кр, 30 ур., все технологии, без наград и конкурентов), mag_tools.dart | s19 | — |

## O. Долгосрочный прогресс и особые события

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| META-01 | Уровень компании | P1 | VERIFIED | 1.68 | — | world_progress.dart | sim | — |
| META-02 | Достижения | P1 | VERIFIED | 1.87 | — | achievements.dart (20 достижений), world_meta.dart (`achievementProgress`, `_checkAchievements`), mag_company.dart («Достижения») | s15, ui_s15 | — |
| META-03 | Первый мегаполис | P1 | VERIFIED | 1.81 | CITY-02 | world_mega.dart (`_megapolisReached`, только поселение-хутор), settlements.dart (`origin`) | megapolis | — |
| META-04 | Постоянная отметка первого мегаполиса | P1 | VERIFIED | 1.81 | META-03 | world_save.dart (`megapolis`), mag_game.dart (золотая корона), награда Мира Финоры | megapolis, ui_rail | Отметка живёт в сохранении партии; новая компания начинает заново (награда в Мире Финоры остаётся) |
| META-05 | История транспортной империи | P2 | VERIFIED | 1.87 | — | world_meta.dart (`chronicle`, `_remember`), mag_company.dart («Летопись») | s15, ui_s15 | Последние 200 событий |
| META-06 | Мегапроекты | P1 | VERIFIED | 1.81 | CONT-08 | megaprojects.dart, world_mega.dart, mag_mega_ui.dart, mag_mega_art.dart | megapolis, ui_rail | — |
| META-07 | Уникальные исторические контракты | P2 | VERIFIED | 1.90 | — | world_network.dart (`historics`, `_offerHistorics`): 5 контрактов по уровням 5–20 | s18 | Не занимают слоты особых контрактов |
| META-08 | Коллекция исторической техники | P3 | VERIFIED | 1.91 | VEH-06 | world_rivals.dart (`collected`, `_collect`: награды за 5/10/15 моделей), mag_rivals_ui.dart (вкладка «Коллекция») | s19, ui_s17 | Учитываются модели, купленные с 1.91, и текущий парк |
| META-09 | Конкурирующие компании | P3 | VERIFIED | 1.91 | META-01 | world_rivals.dart (`MagRival`, `_dayRivals`: 2 конкурента с 5 ур., занимают предприятие раз в 6 дней, оплата там −20%), mag_route_art.dart (цветная точка), mag_rivals_ui.dart | s19, ui_s17 | Конкуренты не возят грузы по карте — их влияние экономическое |
| META-10 | Поглощения компаний | P3 | VERIFIED | 1.91 | META-09 | world_rivals.dart (`acquireRival`, `rivalValue`), mag_rivals_ui.dart (вкладка «Конкуренты») | s19, ui_s17 | — |
| META-11 | Различные сценарии старта | P2 | VERIFIED | 1.89 | — | world_complex.dart (`MagScenario`, `_applyScenario`), mag_tools.dart (выбор при новой игре) | s17, ui_s17 | 5 сценариев |
| META-12 | Развитие после 10-го уровня | P3 | VERIFIED | 1.91 | META-03 | world_rivals.dart (`starsOf`, `_dayStars`: до 5 звёзд, +5% рынка и +10% жителей за звезду), mag_city.dart | s19 | — |
