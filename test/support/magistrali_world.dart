import 'package:finora/domain/magistrali/magistrali.dart';

/// A new company that already learned the combustion engine and drives a
/// pickup instead of the starting cart — for tests of truck logic written
/// before the horse era (the rules they check did not change).
MagWorld motorStart([int seed = MagRules.defaultSeed]) {
  final w = MagWorld.start(seed);
  w.techs.add('combustion');
  w.vehicles.clear();
  final money = w.money;
  w.money += MagRules.truck('pickup')!.price;
  w.buyTruck('pickup');
  w.money = money;
  w.month.expense.remove('vehicles');
  w.vehicles.values.single.name = 'Пикап №1';
  return w;
}
