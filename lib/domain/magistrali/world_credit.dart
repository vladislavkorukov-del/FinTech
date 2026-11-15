part of 'world.dart';

/// A bond the company issued (FIN-18): its sum, the monthly coupon rate and
/// the tick it is paid back.
class MagBond {
  MagBond(this.amount, this.rate, this.until);
  final int amount, until;
  final double rate;
}

/// Stage S24: the credit rating (FIN-17) and bonds (FIN-18), insurance
/// against disasters (INS-01).
extension MagWorldCredit on MagWorld {
  // ---- FIN-17 ----

  static const ratings = ['AAA', 'AA', 'A', 'BBB', 'BB', 'B', 'CCC'];

  /// 0..100: little debt for its size, no days in the minus, months in
  /// profit and a grown company score higher.
  int get creditScore {
    final value = math.max(1, companyValue);
    final owed = debt + bondsOwed;
    var s = 60.0;
    s -= (owed / value) * 80;
    s -= math.min(30, negativeDays * 2).toDouble();
    if (money < 0) s -= 15;
    final recent = months.length > 3
        ? months.sublist(months.length - 3)
        : months;
    for (final m in recent) {
      s += m.profit > 0 ? 6 : -6;
    }
    s += math.min(15, level * .6);
    return s.round().clamp(0, 100);
  }

  /// The letter: AAA at 90 and more down to CCC under 25.
  String get rating {
    final s = creditScore;
    const steps = [90, 80, 70, 55, 40, 25];
    for (var k = 0; k < steps.length; k++) {
      if (s >= steps[k]) return ratings[k];
    }
    return ratings.last;
  }

  /// Interest as a share of the usual rate (living worlds; 1 otherwise).
  double get ratingInterest => !livingWorld
      ? 1
      : const [.6, .7, .85, 1.0, 1.25, 1.6, 2.2][ratings.indexOf(rating)];

  /// The bank's limit as a share of the usual one.
  double get ratingLimit => !livingWorld
      ? 1
      : const [2.0, 1.7, 1.4, 1.0, .8, .5, .25][ratings.indexOf(rating)];

  // ---- FIN-18 ----

  int get bondsOwed => bonds.fold(0, (s, b) => s + b.amount);

  /// The monthly coupon a new bond would carry now.
  double get bondRate => MagRules.bondCoupon * ratingInterest;

  String? issueBond(int amount) {
    if (amount <= 0) return 'Сумма должна быть больше нуля';
    if (rating == 'CCC') return 'С рейтингом CCC облигации никто не купит';
    final room = (companyValue * MagRules.bondShare).round() - bondsOwed;
    if (amount > room) return 'Рынок возьмёт не больше ${math.max(0, room)} кр';
    bonds.add(
      MagBond(
        amount,
        bondRate,
        tick + MagRules.bondDays * MagRules.ticksPerDay,
      ),
    );
    money += amount;
    journal.add(
      tick: tick,
      kind: MagEntryKind.financing,
      category: 'bonds',
      amount: amount,
    );
    _remember('Выпущены облигации на $amount кр');
    _say('Облигации размещены: +$amount кр');
    return null;
  }

  void _dayBonds() {
    final due = bonds.where((b) => b.until <= tick).toList();
    for (final b in due) {
      bonds.remove(b);
      money -= b.amount;
      journal.add(
        tick: tick,
        kind: MagEntryKind.financing,
        category: 'bonds_repay',
        amount: -b.amount,
      );
      _say('Облигации погашены: −${b.amount} кр');
    }
    if (day % MagRules.daysPerMonth != 0) return;
    for (final b in bonds) {
      final coupon = (b.amount * b.rate).round();
      if (coupon > 0) _spend(coupon, 'coupons');
    }
  }

  // ---- INS-01 ----

  /// The monthly premium: a share of what the company is worth.
  int get insurancePremium => math.max(
    MagRules.premiumMin,
    (companyValue * MagRules.premiumShare).round(),
  );

  String? setInsured(bool on) {
    if (on == insured) return null;
    if (on && money < insurancePremium) {
      return 'Не хватает на первый взнос: $insurancePremium кр';
    }
    insured = on;
    if (on) _spend(insurancePremium, 'insurance');
    _say(on ? 'Компания застрахована' : 'Страховка отключена');
    return null;
  }

  /// Monthly premium; the insurer pays for what the weather breaks.
  void _dayInsurance() {
    if (!insured || day % MagRules.daysPerMonth != 0) return;
    _spend(insurancePremium, 'insurance');
  }

  /// When the weather breaks roads: insured, the cells mend in a day and
  /// the insurer pays for the loss.
  void _insuredDamage(List<int> cells) {
    if (!insured) return;
    for (final c in cells) {
      damaged[c] = tick + MagRules.ticksPerDay;
    }
    final pay = cells.length * MagRules.insurancePayout;
    _earn(pay, 'insurance_payout');
    _say('Страховка: ремонт за день, выплата +$pay кр');
  }

  // ---- Saves ----

  Map<String, Object> _saveCredit() => {
    if (bonds.isNotEmpty)
      'bonds': [
        for (final b in bonds) [b.amount, b.rate, b.until],
      ],
    if (insured) 'insured': true,
    ..._savePorts(), // S25
  };

  void loadCredit(Map<String, dynamic> j) {
    for (final raw in j['bonds'] as List? ?? const []) {
      final l = raw as List;
      bonds.add(MagBond(l[0] as int, (l[1] as num).toDouble(), l[2] as int));
    }
    insured = j['insured'] as bool? ?? false;
    loadPorts(j); // S25
  }
}
