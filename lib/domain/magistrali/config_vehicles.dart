/// The vehicle models of the game, from the horse cart to the diesel
/// locomotive (see config.dart).
library;

import 'config.dart';

const magTruckModels = <MagTruckModel>[
  // Era I — horses.
  MagTruckModel(
    id: 'cart',
    name: 'Телега «Гнедко»',
    speed: .75,
    capacity: 6,
    price: 650,
    runningCost: .08,
    upkeep: 2,
    level: 1,
    color: 0xFF9A6A3A,
    horse: true,
  ),
  MagTruckModel(
    id: 'wagon',
    name: 'Фургон «Пара гнедых»',
    speed: .9,
    capacity: 12,
    price: 1800,
    runningCost: .14,
    upkeep: 4,
    level: 2,
    color: 0xFF6F4E37,
    horse: true,
  ),
  // Era III — trucks (open with «Двигатель внутреннего сгорания» in new
  // games; older companies have them already).
  MagTruckModel(
    id: 'pickup',
    name: 'Пикап «Старт»',
    speed: 1.25,
    capacity: 10,
    price: 2200,
    runningCost: .5,
    upkeep: 4,
    level: 1,
    color: 0xFF2BB59A,
  ),
  MagTruckModel(
    id: 'lorry',
    name: 'Грузовик «Терра»',
    speed: 1.4,
    capacity: 22,
    price: 6800,
    runningCost: .9,
    upkeep: 8,
    level: 3,
    color: 0xFFE28A3B,
  ),
  MagTruckModel(
    id: 'tractor',
    name: 'Тягач «Магистраль»',
    speed: 1.6,
    capacity: 38,
    price: 16500,
    runningCost: 1.4,
    upkeep: 14,
    level: 6,
    color: 0xFF4A6FD8,
  ),
  // Era II — railways (stage S8): a locomotive plus wagons.
  MagTruckModel(
    id: 'steam',
    name: 'Паровоз «Искра»',
    speed: 1.5,
    capacity: 0,
    price: 12000,
    runningCost: .7,
    upkeep: 10,
    level: 6,
    color: 0xFF3B3F44,
    rail: true,
    wagonCapacity: 18,
    maxWagons: 4,
    wagonPrice: 1600,
  ),
  MagTruckModel(
    id: 'diesel',
    name: 'Тепловоз «Восток»',
    speed: 2,
    capacity: 0,
    price: 30000,
    runningCost: 1.1,
    upkeep: 18,
    level: 12,
    color: 0xFFC0473F,
    rail: true,
    wagonCapacity: 24,
    maxWagons: 8,
    wagonPrice: 2400,
  ),
];
