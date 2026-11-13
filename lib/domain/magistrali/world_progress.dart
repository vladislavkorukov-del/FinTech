part of 'world.dart';

/// What opens at a company level (for the progression list).
class MagUnlock {
  const MagUnlock(this.level, this.title, {this.soon = false});
  final int level;
  final String title;

  /// Planned for a later stage of the game.
  final bool soon;
}

/// Company levels, contracts and the guided start.
extension MagWorldProgress on MagWorld {
  /// Total experience needed to reach level [n] (no top: it goes on past
  /// 100).
  static int xpFor(int n) => n <= 1 ? 0 : (40 * math.pow(n - 1, 2.2)).round();

  int get level {
    var l = 1;
    while (xp >= xpFor(l + 1)) {
      l++;
    }
    return l;
  }

  /// Highest upgrade level a truck may take now.
  int get maxUpgradeLevel =>
      math.min(MagRules.maxUpgrade, 2 + (level - 1) ~/ 3);

  int get contractSlots => 1 + (level >= 4 ? 1 : 0) + (level >= 8 ? 1 : 0);

  static const unlocks = [
    MagUnlock(1, 'Пикап «Старт» и грунтовые дороги'),
    MagUnlock(2, 'Асфальтовые дороги'),
    MagUnlock(3, 'Грузовик «Терра»'),
    MagUnlock(4, 'Второй контракт'),
    MagUnlock(6, 'Тягач «Магистраль»'),
    MagUnlock(8, 'Третий контракт'),
    MagUnlock(10, 'Депо и ремонтные базы', soon: true),
    MagUnlock(12, 'Скоростное шоссе'),
    MagUnlock(15, 'Железные дороги и поезда', soon: true),
    MagUnlock(20, 'Логистические терминалы', soon: true),
    MagUnlock(25, 'Морские порты и суда', soon: true),
    MagUnlock(30, 'Автомагистрали'),
    MagUnlock(40, 'Крупные транспортные контракты'),
  ];

  static const tasks = [
    MagTask(
      1,
      'Дорога к заводу',
      'Выберите «Стройка» и проведите пальцем дорогу от фермы «Колос» к пищевому заводу «Нива».',
      500,
      40,
    ),
    MagTask(
      2,
      'Первый маршрут',
      'Откройте «Маршруты» и создайте линию: ферма «Колос» → завод «Нива».',
      200,
      20,
    ),
    MagTask(
      3,
      'Грузовик в рейс',
      'Назначьте пикап на маршрут — дальше он ездит сам.',
      200,
      20,
    ),
    MagTask(
      4,
      'Первая доставка',
      'Дождитесь, пока зерно доедет до завода.',
      400,
      30,
    ),
    MagTask(
      5,
      'Прокачка',
      'В «Улучшениях» поднимите двигатель или кузов пикапа.',
      300,
      30,
    ),
    MagTask(
      6,
      'Хлеб в деревню',
      'Постройте дорогу от завода к деревне и возите продукты.',
      800,
      60,
    ),
    MagTask(7, 'Автопарк растёт', 'Купите второй грузовик.', 600, 40),
    MagTask(
      8,
      'Компания 5 уровня',
      'Развивайте перевозки до 5 уровня.',
      1500,
      0,
    ),
  ];

  bool _taskMet(int id) => switch (id) {
    1 => connected(map.startFarm, map.startPlant),
    2 => routes.values.any(
      (r) =>
          r.stops.contains(map.startFarm.id) &&
          r.stops.contains(map.startPlant.id),
    ),
    3 => vehicles.values.any((v) => v.routeId != null),
    4 => deliveries > 0,
    5 => vehicles.values.any((v) => v.upgrades.any((u) => u > 0)),
    6 => (delivered[MagCargo.food] ?? 0) > 0,
    7 => vehicles.length >= 2,
    8 => level >= 5,
    _ => false,
  };

  /// The first task not done yet (null: the start is complete).
  MagTask? get currentTask =>
      tasks.where((t) => !tasksDone.contains(t.id)).firstOrNull;

  /// Pays every task whose condition holds, in order, each once.
  void _checkTasks() {
    for (final t in tasks) {
      if (tasksDone.contains(t.id) || !_taskMet(t.id)) continue;
      tasksDone.add(t.id);
      _earn(t.reward, 'bonus');
      _say('Задание «${t.title}» выполнено: +${t.reward} кр');
      if (t.xp > 0) _gainXp(t.xp);
    }
  }

  /// Checks tasks after an action of the player.
  void checkTasks() => _checkTasks();

  void _gainXp(int n) {
    final before = level;
    xp += n;
    final after = level;
    if (after > before) {
      _say('Уровень компании $after!');
      _refillContracts();
    }
  }

  /// Rewards for the shared Finora world earned here (each pays once).
  List<String> get earnedRewards => [
    if (deliveries > 0) 'magistrali:first_delivery:v1',
    for (var l = 5; l <= math.min(level, 100); l += 5) 'magistrali:level:$l:v1',
  ];

  int _random(int max) {
    rng = (rng * 1103515245 + 12345) & 0x7fffffff;
    return rng % max;
  }

  void _refillContracts() {
    if (rng == 1) rng = seed & 0x7fffffff | 1;
    while (contracts.length < contractSlots) {
      final targets = map.industries
          .where((i) => i.spec.accepts.isNotEmpty)
          .toList();
      final to = targets[_random(targets.length)];
      final cargos = to.spec.accepts.toList()
        ..sort((a, b) => a.index - b.index);
      final cargo = cargos[_random(cargos.length)];
      final big = level >= 40 ? 2 : 1;
      final amount = (30 + _random(40) + level * 3) * big;
      final reward = (amount * MagRules.cargoRate[cargo]! * 22 + level * 60)
          .round();
      contracts.add(
        MagContract(
          id: nextId++,
          cargo: cargo,
          to: to.id,
          amount: amount,
          reward: reward,
          xp: reward ~/ 12,
        ),
      );
    }
  }

  void _countContracts(MagCargo cargo, int to, int n) {
    for (final c in contracts.toList()) {
      if (c.cargo != cargo || c.to != to || c.done) continue;
      c.delivered = math.min(c.amount, c.delivered + n);
      if (c.done) {
        contracts.remove(c);
        _earn(c.reward, 'contracts');
        _gainXp(c.xp);
        _say('Контракт выполнен: +${c.reward} кр');
      }
    }
    _refillContracts();
  }

  /// Swaps a contract for a new one (costs a little).
  String? replaceContract(int id) {
    final c = contracts.where((c) => c.id == id).firstOrNull;
    if (c == null) return 'Нет такого контракта';
    const fee = 150;
    if (money < fee) return 'Не хватает кредитов';
    _spend(fee, 'contracts');
    contracts.remove(c);
    _refillContracts();
    return null;
  }
}
