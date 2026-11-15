# FINORA: Магистрали — каталог игровых механик

Единый источник требований: каждая механика с постоянным ID, приоритетом,
реальным статусом (по исходному коду, а не по плану), этапом, зависимостями,
файлами, тестами и известными проблемами. ID не меняются при перестановке
этапов. Каталог обновляется в конце каждого этапа.

Статусы: NOT_STARTED — не начато; PARTIAL — частично; IN_PROGRESS — в работе;
READY_FOR_REVIEW — готово, ждёт проверки игроком; VERIFIED — проверено игроком
(этапы, которые игрок подтвердил: 1.68–2.0); BLOCKED — заблокировано.

Файлы домена — `lib/domain/magistrali/`, интерфейса —
`lib/presentation/screens/world/magistrali/`. Тесты — `test/magistrali_<имя>_test.dart`
(sim, orders, storage, dispatch, towns, horses, production, growth,
industry, cities, logistics, rail, water, megapolis, passengers, p1, s12, s13, s14, s15, s16, s17, s18, s19, s20, s21, s22, s23, s24, s25, s26, s27, s28, s29, soak, ui, ui_s17, ui_s15, ui_s13, ui_stage5, ui_rail).

Аудит: 1.77.0, обновлено в 1.78.0 (S7) и 1.79.0 (S8), 1.80.0 (S9 и доводка ЖД), 1.81.0 (S10 и графика), 1.82.0 (S11), 1.83.0 (доделка P1), 1.84.0 (S12), 1.85.0 (S13), 1.86.0 (S14), 1.87.0 (S15), 1.88.0 (S16), 1.89.0 (S17), 1.90.0 (S18), 1.91.0 (S19), 1.92.0 (S20), 1.93.0 (S21), 1.94.0 (S22), 1.95.0 (S23), 1.96.0 (S24), 1.97.0 (S25), 1.98.0 (S26), 1.99.0 (S27), 2.0.0 (S28), 2.1.0 (S29); точка восстановления — тег `restore/magistrali-1.77.0-pre-s7`.

## Сводка

| Статус | Механик |
|---|---|
| VERIFIED | 243 |
| READY_FOR_REVIEW | 6 |
| PARTIAL | 0 |
| NOT_STARTED | 0 |
| Всего | 249 |

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
| CORE-10 | Лог ошибок симуляции | P1 | VERIFIED | 1.92 | — | world_finish.dart (`simErrors`, `_safely`: ошибка машины останавливает только её; `_checkLedger`: учёт грузов исправляется ежедневно), mag_finish_ui.dart («Карта, регионы и журнал») | s20, soak, ui_s15 | — |

## B. Поселения и развитие городов

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| CITY-01 | Независимое состояние поселений | P0 | VERIFIED | 1.72 | CITY-03 | settlements.dart, world_settlements.dart | towns | — |
| CITY-02 | Десять уровней развития | P1 | VERIFIED | 1.81 | — | settlements.dart (уровни 8–10: сталь, детали, кирпич в нуждах и росте; мегапроекты) | towns, megapolis | — |
| CITY-03 | Многоклеточная территория | P0 | VERIFIED | 1.72 | — | settlements.dart (`cells`), map.dart | towns | — |
| CITY-04 | Автоматическое расширение | P1 | VERIFIED | 1.72 | CITY-03 | world_settlements.dart (`_growTown`), map.dart (`expandCells`) | towns, growth | — |
| CITY-05 | Защита инфраструктуры | P0 | VERIFIED | 1.72 | CITY-04 | world_settlements.dart (`_townLandFree`) | towns: «growth blocked by roads» | — |
| CITY-06 | Изменение застройки | P1 | VERIFIED | 1.92 | CITY-03 | mag_town_levels.dart (своя деталь застройки и центра на каждом из 10 уровней), mag_town_art.dart, mag_city_art.dart | — | — |
| CITY-07 | Население | P1 | VERIFIED | 1.92 | CITY-01 | world_finish.dart (`populationFactor`: ежедневные нужды растут с населением до ×1,5), world_settlements.dart | s20, towns, growth | — |
| CITY-08 | Потребности города | P1 | VERIFIED | 1.77 | CITY-02, CORE-03 | settlements.dart (`needs`, `marketGoods`), world_cities.dart | cities | — |
| CITY-09 | Контракты развития | P1 | VERIFIED | 1.75 | CITY-08 | world_settlements.dart (`_payDevelopment`; 1.92: рост — одна шкала `growthProgress`, без порога населения) | growth | — |
| CITY-10 | Транспортная доступность | P1 | VERIFIED | 1.92 | ROAD-12 | world_finish.dart (`accessModes`, `accessFactor`: +25% к притоку жителей за каждый вид транспорта сверх первого), mag_finish_ui.dart | s20, ui_s15 | — |
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
| TECH-05 | Современная логистика | P1 | VERIFIED | 1.92 | LOG-07 | world_finish.dart (`eraName`: эпохи I–V, IV — диспетчерская и шоссе), mag_fleet.dart | s20 | — |
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
| ROAD-09 | Дорожные заторы | P3 | VERIFIED | 1.92 | ROAD-08 | world_routes.dart (`congestionOf`), world_finish.dart (`jams`), world_advice.dart (совет «Пробки») | s13, s20 | — |
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
| PROD-10 | Машиностроение | P2 | VERIFIED | 1.93 | PROD-08 | config_industries.dart (`machineWorks`: 2 стали + деталь → станок), config.dart (груз `machines`), tech_nodes_recipes.dart (`machinetools`), mag_machine_art.dart, settlements.dart (станки покупают города с 6 ур.) | s21 | Станкозавод строит только игрок |
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
| BIZ-12 | Специализация регионов | P2 | VERIFIED | 1.92 | CITY-11 | world_finish.dart (`regionSpecialization`, `regionFactor`: свои добытчики профиля региона +10%), mag_finish_ui.dart | s20 | — |
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
| CONT-10 | Субсидируемые маршруты | P2 | VERIFIED | 1.93 | — | world_biomes.dart (`subsidies`, `_daySubsidies`: города с 4 ур. платят +40% на линии 25 дней), world_cities.dart (спрос недели), mag_finish_ui.dart (`subsidyCards`, кнопка «Маршрут») | s21, ui_s13 | — |
| CONT-11 | Уникальные дорогие заказы | P2 | VERIFIED | 1.93 | — | world_biomes.dart (`magUniqueOrders`: 8 именных заказов городов 5–10 ур., каждый один раз за игру), world_cities.dart (городские заказы) | s21 | — |
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
| LOG-13 | Автоэкспорт излишков | P2 | VERIFIED | 1.92 | — | world_storage.dart (распределение склада), world_finish.dart (`autoExport`, `_dayExport`: свои предприятия продают сверх 80% склада за полцены) | s20 | — |
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
| SEA-06 | Мультимодальные терминалы | P2 | VERIFIED | 1.92 | SEA-01, RAIL-02 | world_finish.dart (`isMultimodal`: склад со станцией и причалом +50% места), mag_warehouse.dart | s20 | — |

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
| FIN-06 | Себестоимость продукции | P1 | VERIFIED | 1.92 | FIN-05 | world_finish.dart (`unitCost`), mag_finish_ui.dart (окно предприятия) | s20 | — |
| FIN-07 | Стоимость активов | P1 | VERIFIED | 1.76 | — | world_finance.dart | industry | Склады не входят в стоимость компании |
| FIN-08 | Финансовый центр | P1 | VERIFIED | 1.76 | FIN-01 | mag_finance.dart | ui_stage5 | — |
| FIN-09 | Исторические графики | P1 | VERIFIED | 1.76 | FIN-02 | mag_finance.dart (12 месяцев) | — | — |
| FIN-10 | Региональная статистика | P2 | VERIFIED | 1.92 | — | world_finish.dart (`regionStats`: 9 регионов — места, свои, выручка), mag_finish_ui.dart | s20, ui_s15 | — |
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
| MAP-04 | Проверка жизнеспособности карты | P0 | VERIFIED | 1.92 | — | map.dart (гарантированная первая линия), world_finish.dart (`chainReport`, `mapViable`: у каждого сырья цепочки есть поставщик в 70 клетках) | sim, s20, ui_s15 | — |
| MAP-05 | Реки и озёра | P1 | VERIFIED | 1.83 | — | map.dart, map_noise.dart (`_carveBigRiver`: большая река делит карту) | p1, sim | — |
| MAP-06 | Леса и поля | P1 | VERIFIED | 1.68 | — | map.dart | sim | — |
| MAP-07 | Горные регионы | P2 | VERIFIED | 1.92 | — | world_finish.dart (`mountains`: хребты от 25 клеток холмов с именами, `mountainFactor`: добыча +20%), mag_decor_cache.dart (названия на карте) | s20 | — |
| MAP-08 | Открытие новых регионов | P2 | VERIFIED | 1.90 | — | world_network.dart (`regionOf`, `openRegion`, 3×3 региона), mag_structures_art.dart, mag_works_ui.dart | s18, ui_s17 | Только в новых компаниях |
| MAP-09 | Разнообразные биомы | P2 | VERIFIED | 1.93 | MAP-08 | world_biomes.dart (`biomeOf`: луга, степь, тайга, нагорье, озёрный край по 9 регионам; бонусы в новых компаниях), mag_decor_cache.dart (оттенок земли, названия вдали), mag_terrain_art.dart, mag_sea_art.dart | s21 | — |
| MAP-10 | Редкие месторождения | P2 | VERIFIED | 1.88 | — | world_works.dart (`isRich`: каждый 6-й добытчик, +50%), mag_structures_art.dart (`paintGem`), mag_works_ui.dart | s16, ui_s15 | Определяются зерном карты |
| MAP-11 | Редактор карты | P3 | VERIFIED | 1.92 | MAP-12 | map.dart (`setTerrain`), world_finish.dart (`editTerrain`, `terrainEdits` в сохранении), mag_build_panel.dart (вкладка «Карта» в песочнице: луг, лес, горы, озеро) | s20 | Только местность; предприятия ставятся обычной стройкой |
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

## P. Живой мир (S22)

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| LIFE-01 | Сезоны года | P2 | VERIFIED | 1.94 | — | world_seasons.dart (`season`: весна, лето, осень, зима по 30 дней; урожай: лето +20%, осень +10%, зима ×0,5), mag_decor_cache.dart (снег, золото осени, весенняя зелень) | s22 | В живом мире: новые компании и сохранения до 1.94 |
| LIFE-02 | Погода | P2 | VERIFIED | 1.94 | LIFE-01 | world_seasons.dart (`weather`: ясно, дождь, снег, туман, шторм по сезону; `weatherSpeed`), mag_atmosphere.dart (`paintWeather`), mag_topbar.dart (плашка сезона и погоды) | s22, ui_s13 | — |
| LIFE-03 | Случайные события | P2 | VERIFIED | 1.94 | — | world_seasons.dart (`_dayEvents`: ярмарка +40%, забастовка, бум спроса +30%, дорогое топливо +40%, городской грант) | s22 | — |
| LIFE-04 | Сюжетная кампания | P2 | VERIFIED | 1.94 | META-01 | world_seasons.dart (`magChapters`: 9 глав с целями и наградами от 2 000 до 300 000 кр), mag_rivals_ui.dart (вкладка «Кампания») | s22, ui_s13 | — |
| AIR-01 | Аэропорты | P2 | VERIFIED | 1.94 | TECH-06 | world_air.dart (`buildAirport`: на ровной земле в 3 клетках от места, 25 000 кр), mag_air_art.dart (полоса и вышка), mag_build_panel.dart («Аэропорт») | s22, ui_s13 | — |
| AIR-02 | Грузовая авиация | P2 | VERIFIED | 1.94 | AIR-01 | config_vehicles.dart (биплан «Кукурузник», грузовой «Атлант»), world_air.dart (`airPath`: по прямой), технологии «Авиация» и «Грузовая авиация», mag_air_art.dart (самолёт и тень) | s22 | — |

## Q. Стихии, биржа и туризм (S23)

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| DIS-01 | Стихийные бедствия | P2 | VERIFIED | 1.95 | LIFE-02 | world_market.dart (`_dayDisasters`: в дождь паводок размывает мост, в бурю ломаются 2 клетки дорог; с 4 ур., живой мир), world_paths.dart (сломанная клетка закрыта), mag_resort_art.dart (`paintDamage`: трещина и заграждения) | s23 | — |
| DIS-02 | Ремонт инфраструктуры | P2 | VERIFIED | 1.95 | DIS-01 | world_market.dart (бригада чинит за 6 дн., у депо за 2; `repairRoad` сразу за деньги), mag_road.dart (кнопка ремонта), world_advice.dart (совет «Повреждены дороги») | s23, ui_s17 | — |
| STK-01 | Акции компании | P2 | VERIFIED | 1.95 | FIN-01 | world_market.dart (`sharePrice` = стоимость / 1000, `issueShares`, `buybackShares`, контроль 510 акций, дивиденды 30% прибыли держателям, история 60 дней), mag_stocks_ui.dart (вкладка «Биржа» с графиком) | s23, ui_s17 | — |
| STK-02 | Акции конкурентов | P2 | VERIFIED | 1.95 | META-10 | world_market.dart (`buyRivalShares`: пакет 51% — поглощение; дивиденды с пакета), mag_stocks_ui.dart | s23 | — |
| TOUR-01 | Курорты | P2 | VERIFIED | 1.95 | PASS-01 | config_industries.dart (`lakeResort` у озера, `skiResort` у гор; технология «Туризм», 8 ур.), mag_resort_art.dart (отель с зонтиками, шале с подъёмником) | s23 | Строит только игрок |
| TOUR-02 | Туристический спрос | P2 | VERIFIED | 1.95 | TOUR-01 | world_market.dart (`tourismFactor`: туристы платят +60%, в сезон курорта ещё ×1,5; курорт отправляет туристов обратно) | s23 | — |
| VIS-01 | Сезонная листва | P3 | VERIFIED | 1.95 | LIFE-01 | mag_terrain_art.dart (`MagFoliage`: осенью рыжая, жёлтая и красная листва, зимой снег на ёлках и голые деревья, весной цветение), mag_decor_cache.dart (вдали — те же цвета) | — | — |

## R. Финансы и круизы (S24)

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| CRED-01 | Кредитный рейтинг | P2 | VERIFIED | 1.96 | FIN-01 | world_credit.dart (`creditScore` 0–100 из долга к стоимости, просрочек, прибыльных месяцев и уровня; `rating` AAA…CCC), mag_stocks_ui.dart (карточка рейтинга на вкладке «Биржа») | s24, ui_s15 | — |
| CRED-02 | Условия кредита по рейтингу | P2 | VERIFIED | 1.96 | CRED-01 | world_meta.dart (`loanLimit` × `ratingLimit` от ×2 до ×0,25; процент × `ratingInterest` от ×0,6 до ×2,2; только в живом мире) | s24 | — |
| BOND-01 | Облигации | P2 | VERIFIED | 1.96 | CRED-01 | world_credit.dart (`issueBond`: 25/50/100 тыс., лимит 50% стоимости, купон 1,5%/мес × рейтинг, погашение через 180 дн.; при CCC рынок закрыт), mag_stocks_ui.dart | s24, ui_s15 | — |
| INS-01 | Страхование от стихии | P2 | VERIFIED | 1.96 | DIS-01 | world_credit.dart (`setInsured`, взнос 0,3% стоимости в месяц, мин. 500; бедствие чинится за 1 день бесплатно, выплата 1 500 кр/клетку), world_market.dart (`repairPrice` = 0) | s24, ui_s15 | — |
| CRU-01 | Круизные лайнеры | P2 | VERIFIED | 1.96 | TOUR-01 | config_vehicles.dart (лайнер «Чайка»: 60 пассажиров, комфорт ×1,6, 70 000 кр, технология «Туризм», 12 ур.), mag_rail_art.dart (белые палубы и красная труба) | s24 | Только пассажиры |
| VIS-02 | Ночные огни аэропортов и курортов | P3 | VERIFIED | 1.96 | AIR-01 | mag_atmosphere.dart (`paintNightLights`: огни вдоль полосы, красный фонарь вышки, окна отелей и шале) | — | — |
| VIS-03 | Плавные устья рек | P3 | VERIFIED | 1.96 | — | mag_sea_art.dart (`_paintMouths`: мягкие круглые разливы от реки к морю без клина и полос), mag_terrain_art.dart (вода доходит до края карты) | — | — |

## S. Порты, сигналы, ипотека, ночные смены (S25)

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| PORT-01 | Контейнерные терминалы | P2 | VERIFIED | 1.97 | SEA-01 | world_ports.dart (`buildContainerTerminal` в порту, 30 000 кр, технология «Контейнерные перевозки»; `handleAt`: суда грузятся ×3), mag_s25_ui.dart (окно порта), mag_port_art.dart (портальный кран и штабели) | s25 | — |
| PORT-02 | Контейнеровоз | P2 | VERIFIED | 1.97 | PORT-01 | config_vehicles.dart (контейнеровоз «Нева»: 240 мест, любые сухие грузы, оплата ×1,2, 56 000 кр, 14 ур.), world_ports.dart (`containerRouteBlocker`: только между терминалами), mag_rail_art.dart (цветные контейнеры) | s25 | Без жидкостей и людей |
| SIG-01 | ЖД-сигналы | P2 | VERIFIED | 1.97 | RAIL-07 | world_ports.dart (`toggleSignal`, 1 500 кр, технология «Железнодорожная сигнализация»; `blockAhead` до следующего сигнала или станции, `_signalRed`: поезд ждёт, пока блок занят; после долгого ожидания — обычные правила), mag_port_art.dart (столб с красным/зелёным огнём) | s25 | — |
| JCT-01 | Развязки | P2 | VERIFIED | 1.97 | ROAD-08 | world_ports.dart (`buildInterchange` на перекрёстке или переезде, 6 000 кр, технология «Развязки»; `freeFlow`: без пробок на клетке и соседних), world_routes.dart (`congestionOf`), mag_port_art.dart (эстакада) | s25 | — |
| MORT-01 | Ипотека для городов | P2 | VERIFIED | 1.97 | CITY-09 | world_ports.dart (`startMortgage`: 15 000 кр × уровень, 180 дн. рост населения ×1,6, возврат ×1,3 помесячно), world_settlements.dart (`mortgageFactor`), mag_s25_ui.dart (карточка в окне поселения) | s25, ui_s15 | — |
| NIGHT-01 | Ночные смены | P2 | VERIFIED | 1.97 | PROD-02 | world_ports.dart (`setNightShift`: выработка +30%, зарплата 40 кр × площадь в день, технология «Ночные смены»), world_industry.dart (`outputFactor`), mag_port_art.dart (окна горят ночью) | s25, ui_s15 | Только свои предприятия |

## T. Свободная стройка, метро, хабы, фьючерсы (S26)

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| VIS-04 | Свободная трассировка дорог и путей | P1 | VERIFIED | 1.98 | ROAD-01 | world_trace.dart (`lineCells`, `planRoadLine`/`planRailLine`: прямая под любым углом, препятствия — в обход; `planTrace`: путь по следу пальца), mag_screen_input.dart (рисование одним пальцем, два — карта), mag_build_panel.dart (переключатель «Рисовать»), mag_curve.dart (`wayLine`: лесенки клеток — в прямую, углы — в дуги; машины едут по той же линии) | s26, ui_stage5 | Под капотом клетки: сохранения и правила те же |
| METRO-01 | Метро в мегаполисах | P2 | VERIFIED | 1.98 | CITY-09 | world_hubs.dart (`buildMetro` с «Регионального центра», 120 000 кр, технология «Метрополитен»; пассажиров ×1,5, рост ×1,2, проезд 0,02 кр с жителя в день), mag_s26_ui.dart (карточка в окне города), mag_port_art.dart (павильон «M») | s26, ui_s15 | — |
| HUB-01 | Сортировочные станции | P2 | VERIFIED | 1.98 | RAIL-02 | world_hubs.dart (`buildYard` на станции, 20 000 кр, технология «Сортировочные станции»; погрузка поездов ×2), mag_s26_ui.dart (окно станции), mag_port_art.dart (веер путей и пост) | s26 | — |
| HUB-02 | Грузовые хабы | P2 | VERIFIED | 1.98 | LOG-01 | world_hubs.dart (`buildHub` на складе, 25 000 кр, технология «Грузовые хабы»; место ×1,5, погрузка ×2), world_storage.dart (`warehouseCapacityOf`), mag_port_art.dart (синий портал) | s26 | — |
| FUT-01 | Фьючерсы на грузы | P2 | VERIFIED | 1.98 | STK-01 | world_hubs.dart (`buyFuture`: залог 15% цены, 30 дн., исполнение — 45% цены, до 3 контрактов, с 12 ур.; счёт доставок через `_countDeals`), mag_s26_ui.dart (карточка на вкладке «Биржа») | s26, ui_s15 | — |
| TOUR-03 | Туристические экскурсии | P2 | VERIFIED | 1.98 | TOUR-02 | world_hubs.dart (`setExcursion`: маршрут от 3 остановок через курорт, туристы платят ×1,5), world_complex.dart (`cargoPayFactor`), mag_s26_ui.dart (переключатель в карточке маршрута) | s26 | — |

## U. Свободная геометрия дорог (S27)

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| VIS-05 | Дороги и пути по свободным кривым | P1 | VERIFIED | 1.99 | VIS-04 | world_ways.dart (`MagWay`: точки кривой в дробных координатах; `wayCurve` — сплайн Катмулла–Рома; `layCurve` — след клеток бок о бок и точка кривой в каждой клетке; `planWay` — план по следу пальца или двум касаниям, концы прилипают к сети; препятствие при двух касаниях — объезд с выпрямлением; сохранение `ways`), mag_ways_art.dart (`MagNet`: кривые, старые цепочки дотягиваются до кривых), mag_curve.dart (машины едут по точкам кривой), mag_screen_input.dart (след пальца без клеток, предпросмотр кривой) | s27, ui_stage5, ui_rail | Под кривой — клетки-след: на них держатся правила; снос клетки убирает кривую (участок рисуется клетками) |
| VIS-06 | Чистые стыки дорог | P2 | VERIFIED | 1.99 | VIS-05 | mag_ways_art.dart (плашка покрытия поверх каждого перекрёстка, ответвления и пересечения кривых — разметка, колеи и края не наслаиваются) | — | — |

## V. Мосты, развязки, трамваи (S28)

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| BRG-01 | Мосты через озёра и эстакады | P1 | VERIFIED | 2.0 | VIS-05 | world_spans.dart (`spansOf`: кривая проходит над озером, а в режиме «Эстакада» — над дорогами и путями; пролёт до 14 клеток по 900 кр; связь через пролёт, запрет боковых шагов к дороге под эстакадой), pathfinding.dart (`links`, `cuts` в A* и компонентах) | s28, ui_s15 | — |
| VIS-08 | Мосты и эстакады по форме кривой | P2 | VERIFIED | 2.0 | BRG-01 | mag_deck_art.dart (настил по кривой с подъёмом и спуском, опоры, перила, покрытие или путь сверху; над рекой — низкий мост вдоль кривой; машины поднимаются на настил) | — | Тоннели — прежние, по клеткам |
| JCT-02 | Развязки всех видов | P1 | VERIFIED | 2.0 | JCT-01 | world_spans.dart (`buildJunction`: эстакада — дорога над дорогой без съезда, 15 000 кр; клевер — эстакада и четыре съезда, 40 000 кр; кольцо — круг вокруг островка, 12 000 кр), mag_s28_ui.dart (кнопки в окне дороги), mag_build_panel.dart (режим «Эстакада» для любой нарисованной трассы) | s28, ui_s15 | Нужен перекрёсток на 2 клетки во все стороны |
| VIS-07 | Снос кривой целиком | P2 | VERIFIED | 2.0 | VIS-05 | world_spans.dart (`removeWayAt`: свои клетки кривой, не нужные другим кривым, с возвратом части цены), mag_s28_ui.dart («Снести всю кривую» в окне дороги и пути) | s28 | — |
| VIS-09 | Плавные переходы между типами дорог | P2 | VERIFIED | 2.0 | VIS-06 | mag_ways_art.dart (`_tapers`: широкая дорога обрезается, клин с градиентом обочины и покрытия сводит ширины; перекрёсток — только при трёх ветках) | — | — |
| TRAM-02 | Трамваи по улицам | P2 | VERIFIED | 2.0 | VEH-12 | world_spans.dart (`tramStreets`: улицы трамвайных маршрутов; `tramFactor`: между поселениями от 4 уровня оплата ×1,25), mag_ways_art.dart (рельсы в мостовой) | s28 | — |

## W. Тоннели, петли, турбина, стек, метро-линии (S29)

| ID | Механика | P | Статус | Версия | Зависимости | Файлы | Тесты | Проблемы |
|---|---|---|---|---|---|---|---|---|
| VIS-10 | Тоннели по форме кривой | P2 | READY_FOR_REVIEW | 2.1 | VIS-05 | mag_ways_art.dart (`_portals`: портал там, где кривая уходит в горы, повёрнут по направлению кривой), mag_structures_art.dart (`paintPortalAt` под любым углом) | — | — |
| JCT-03 | Клевер с настоящими петлями | P1 | READY_FOR_REVIEW | 2.1 | JCT-02 | world_spans.dart (`_ramps`: в каждой четверти петля на 270° вокруг центра в стороне от дорог; нужны дороги на 4 клетки во все стороны, 40 000 кр); форма развязки не прореживается (`planWay(thin: false)`) | s29 | — |
| JCT-04 | Развязка «турбина» | P2 | READY_FOR_REVIEW | 2.1 | JCT-02 | world_spans.dart (эстакада и четыре закрученных съезда, 55 000 кр) | s29 | — |
| JCT-05 | Трёхуровневые развязки | P1 | READY_FOR_REVIEW | 2.1 | BRG-01 | world_spans.dart («Стек»: эстакада и четыре съезда над перекрёстком, 80 000 кр), mag_deck_art.dart (`deckLevels`: мост над мостом — уровнем выше, до трёх; короткий настил не задирается) | s29 | Любая эстакада над эстакадой — тоже третий уровень |
| METRO-02 | Линии метро под городом | P2 | READY_FOR_REVIEW | 2.1 | METRO-01 | world_metro.dart (`buildMetroLine` между городами с метро до 40 клеток, 3 000 кр за клетку; проезд 1% населения обоих городов в день; рост +10% за линию, до трёх), mag_port_art.dart (`paintMetroLines`: две цветные линии со станциями под каждым городом с метро, пунктир линий между городами), mag_s26_ui.dart (кнопки линий в карточке метро) | s29 | — |
| VIS-11 | Фонари вдоль шоссе и магистралей | P3 | READY_FOR_REVIEW | 2.1 | — | mag_ways_art.dart (`_lamps`: столбы каждые 1,5 клетки по обе стороны; ночью — свет) | — | — |
