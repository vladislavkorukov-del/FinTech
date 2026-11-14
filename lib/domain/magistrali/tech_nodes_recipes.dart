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
];
