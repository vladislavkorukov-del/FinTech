part of 'world.dart';

/// One tutorial task: done when its condition holds and the one before is
/// done. Rewards are granted outside, once per id (see FinorioRewards).
class FinTask {
  const FinTask(this.id, this.title, this.hint);
  final int id;
  final String title, hint;
  String get rewardId => 'finorio:task:$id:v1';
}

abstract final class FinTasks {
  static const all = <FinTask>[
    FinTask(
      1,
      'Поставьте буровую на месторождение',
      'Выберите буровую внизу и коснитесь клетки с рудой.',
    ),
    FinTask(
      2,
      'Подайте энергию буровой',
      'Поставьте генератор рядом (в радиусе 6 клеток) и загрузите биомассу.',
    ),
    FinTask(
      3,
      'Постройте конвейер',
      'Буровая выдаёт руду в клетку перед собой — начните конвейер оттуда.',
    ),
    FinTask(
      4,
      'Передайте руду в плавильную печь',
      'Направьте конвейер в печь: она сама выберет рецепт по руде.',
    ),
    FinTask(
      5,
      'Получите 10 металлических пластин',
      'Печи тоже нужна энергия. Готовые пластины выходят вперёд.',
    ),
    FinTask(
      6,
      'Постройте сборочный станок',
      'Поставьте станок и выберите рецепт в его панели.',
    ),
    FinTask(
      7,
      'Автоматически изготовьте 10 шестерён',
      'Подведите пластины к станку с рецептом «Шестерня».',
    ),
    FinTask(
      8,
      'Наладьте выпуск электронных схем',
      'Схеме нужны медная пластина и кристалл: два конвейера в один станок.',
    ),
    FinTask(
      9,
      'Подайте 5 схем в исследовательский терминал',
      'Терминал принимает схемы для текущего исследования.',
    ),
    FinTask(
      10,
      'Откройте улучшенную логистику',
      'Когда схемы собраны, терминалу нужна энергия на исследование.',
    ),
  ];
  static const researchRewardId = 'finorio:research:logistics:v1';
}

extension FinWorldTasks on FinWorld {
  int made(FinItem i) => created[i] ?? 0;

  bool _taskHolds(int id) => switch (id) {
    1 => machines.values.any((m) => m.kind == FinBuilding.drill),
    2 => machines.values.any(
      (m) => m.kind == FinBuilding.drill && m.powered > 0,
    ),
    3 => machines.values.any((m) => m.isBelt),
    4 => furnaceOre > 0,
    5 => made(FinItem.ironPlate) + made(FinItem.copperPlate) >= 10,
    6 => machines.values.any((m) => m.kind == FinBuilding.assembler),
    7 => made(FinItem.gear) >= 10,
    8 => made(FinItem.circuit) >= 3,
    9 => labDelivered >= 5,
    10 => researched.contains('logistics'),
    _ => false,
  };

  void _checkTasks() {
    for (final t in FinTasks.all) {
      if (tasksDone.contains(t.id)) continue;
      if (t.id > 1 && !tasksDone.contains(t.id - 1)) return;
      if (!_taskHolds(t.id)) return;
      tasksDone.add(t.id);
    }
  }

  /// Checks the tasks now (after an action, without waiting for a tick).
  void checkTasks() => _checkTasks();

  /// The first task not yet done, or null when the tutorial is finished.
  FinTask? get currentTask =>
      FinTasks.all.where((t) => !tasksDone.contains(t.id)).firstOrNull;

  /// Rewards this factory has earned (task and research ids).
  List<String> get earnedRewards => [
    for (final t in FinTasks.all)
      if (tasksDone.contains(t.id)) t.rewardId,
    if (researched.contains('logistics')) FinTasks.researchRewardId,
  ];
}
