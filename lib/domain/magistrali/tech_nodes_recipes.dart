/// Recipes by technology (TECH-10, 1.83): the processing businesses the
/// company may build open with a technology, not with the company level
/// alone (see `MagIndustrySpec.tech`).
library;

import 'tech.dart';

const magTechRecipes = <MagTech>[
  MagTech(
    id: 'milling',
    branch: MagBranch.economy,
    title: 'Мукомольное дело',
    lore:
        'Жернова, сита и пекарь из соседней губернии: зерно можно '
        'перемолоть в муку, а муку — испечь в хлеб.',
    effect: 'Открывает строительство мельниц и пекарен',
    effects: {},
    cost: 2500,
    level: 2,
  ),
  MagTech(
    id: 'carpentry',
    branch: MagBranch.economy,
    title: 'Столярное дело',
    lore: 'Пилорама и сушильня: брёвна превращаются в ровные доски.',
    effect: 'Открывает строительство лесопилок',
    effects: {},
    cost: 2500,
    level: 2,
  ),
  MagTech(
    id: 'kilns',
    branch: MagBranch.economy,
    title: 'Обжиг кирпича',
    lore: 'Печи, формы и сухая глина: город начинает строиться из кирпича.',
    effect: 'Открывает глиняные карьеры и кирпичные заводы',
    effects: {},
    cost: 4500,
    level: 3,
  ),
  MagTech(
    id: 'metallurgy',
    branch: MagBranch.economy,
    title: 'Металлургия',
    lore: 'Домна, кокс и мастера-литейщики: руда и уголь становятся сталью.',
    effect: 'Открывает угольные шахты и сталелитейные заводы',
    effects: {},
    cost: 8000,
    level: 4,
    requires: ['kilns'],
  ),
  MagTech(
    id: 'machinery',
    branch: MagBranch.economy,
    title: 'Машиностроение',
    lore: 'Станки и чертежи: из стали и досок собирают детали машин.',
    effect: 'Открывает заводы деталей',
    effects: {},
    cost: 11000,
    level: 5,
    requires: ['metallurgy'],
  ),
  // Stage S17.
  MagTech(
    id: 'petroleum',
    branch: MagBranch.economy,
    title: 'Нефтедобыча',
    lore:
        'Буровые вышки и перегонный куб: из-под земли — нефть, из нефти — топливо.',
    effect: 'Открывает нефтяные вышки, НПЗ и цистерны',
    effects: {},
    cost: 9000,
    level: 6,
    requires: ['metallurgy'],
  ),
  MagTech(
    id: 'electronics',
    branch: MagBranch.economy,
    title: 'Электроника',
    lore: 'Платы, лампы и паяльники: детали и топливо превращаются в технику.',
    effect: 'Открывает заводы электроники',
    effects: {},
    cost: 16000,
    level: 9,
    requires: ['machinery', 'petroleum'],
  ),
  MagTech(
    id: 'aviation',
    branch: MagBranch.fleet,
    title: 'Авиация',
    lore:
        'Взлётная полоса, диспетчерская вышка и первые самолёты — по прямой, над реками и горами.',
    effect: 'Открывает аэропорты и биплан «Кукурузник»',
    effects: {},
    cost: 40000,
    level: 16,
    requires: ['combustion'],
  ),
  MagTech(
    id: 'jetcargo',
    branch: MagBranch.fleet,
    title: 'Грузовая авиация',
    lore:
        'Реактивные двигатели и большие трюмы: самолёт везёт сорок тонн за полдня.',
    effect: 'Открывает грузовой самолёт «Атлант»',
    effects: {},
    cost: 90000,
    level: 20,
    requires: ['aviation'],
  ),
  MagTech(
    id: 'machinetools',
    branch: MagBranch.economy,
    title: 'Станкостроение',
    lore:
        'Токарные и фрезерные станки: сталь и детали превращаются в оборудование для заводов.',
    effect: 'Открывает станкостроительные заводы (станки — самый дорогой груз)',
    effects: {},
    cost: 20000,
    level: 11,
    requires: ['machinery'],
  ),
  MagTech(
    id: 'electrotransport',
    branch: MagBranch.economy,
    title: 'Электротранспорт',
    lore:
        'Провода над улицами и звонкие вагоны: трамвай везёт сразу шестьдесят человек.',
    effect: 'Открывает трамваи между поселениями',
    effects: {},
    cost: 12000,
    level: 10,
    requires: ['electronics'],
  ),
  // Transport of the future (TECH-06, 1.91).
  MagTech(
    id: 'autopilot',
    branch: MagBranch.fleet,
    title: 'Автопилот',
    lore: 'Лидары, карты и спокойный компьютер за рулём: грузовик едет сам.',
    effect: 'Открывает беспилотные грузовики',
    effects: {MagBonus.speed: .03},
    cost: 40000,
    level: 22,
    requires: ['electronics'],
  ),
  MagTech(
    id: 'maglev',
    branch: MagBranch.fleet,
    title: 'Магнитная подвеска',
    lore: 'Поезд парит над путём: ни колёс, ни трения — только скорость.',
    effect: 'Открывает маглевы',
    effects: {MagBonus.speed: .02},
    cost: 60000,
    level: 25,
    requires: ['autopilot'],
  ),
];
