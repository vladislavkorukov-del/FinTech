part of 'world.dart';

/// What a piece of advice is about.
enum MagAdviceKind {
  lossBusiness,
  noInput,
  stockFull,
  idleVehicle,
  lossRoute,
  emptyRoute,
  warehouseFull,
  centerIdle,
  trainsBlocked,
  cityDemand,
}

/// One piece of advice: what is wrong (or what could pay), the figures it
/// rests on, and where to look. Advice never promises a profit.
class MagAdvice {
  const MagAdvice(
    this.kind,
    this.title,
    this.detail, {
    this.place,
    this.vehicle,
    this.route,
    this.weight = 1,
  });
  final MagAdviceKind kind;
  final String title, detail;
  final int? place, vehicle, route;

  /// Larger first.
  final int weight;
}

/// Problems and recommendations (stage S7: FIN-11, FIN-12, LOG-18) worked
/// out from the company's real figures: losses with their likely cause,
/// stock nobody carries away, plants without input, idle vehicles,
/// unprofitable or mostly empty lines, full warehouses, centres that
/// cannot work, and a city's demand of the week the company could serve.
extension MagWorldAdvice on MagWorld {
  /// Days something has been the company's (null: not known).
  double? _ownedDays(MagIndustry i) =>
      i.since == null ? null : (tick - i.since!) / MagRules.ticksPerDay;

  List<MagAdvice> get advice {
    final out = <MagAdvice>[];
    for (final i in map.industries) {
      if (i.owned && i.kind != MagIndustryKind.logisticsCenter) {
        final inputs = {...i.spec.converts.keys, ...i.spec.extra.keys};
        final dry = [
          for (final c in inputs)
            if ((i.input[c] ?? 0) == 0 && orders.reservedIn(i.id, c) == 0) c,
        ];
        final full = [
          for (final c in i.supplies)
            if ((i.stock[c] ?? 0) >= outputCapOf(i)) c,
        ];
        final days = _ownedDays(i);
        final profit = i.revenue - i.costs;
        if (days != null && days >= 10 && profit < 0) {
          final why = dry.isNotEmpty
              ? 'нет сырья'
              : full.isNotEmpty
              ? 'продукцию не вывозят'
              : i.sold == 0 && i.produced > 0
              ? 'продукцию никто не покупает — везите её покупателям'
              : 'расходы выше продаж';
          out.add(
            MagAdvice(
              MagAdviceKind.lossBusiness,
              '${i.name}: убыток ${magAmount(-profit)} кр',
              'За ${days.round()} дн.: продажи ${magAmount(i.revenue)}, расходы ${magAmount(i.costs)}. Причина: $why.',
              place: i.id,
              weight: 5,
            ),
          );
        }
        if (dry.isNotEmpty) {
          out.add(
            MagAdvice(
              MagAdviceKind.noInput,
              '${i.name} стоит без сырья',
              'Пусто: ${dry.map(magCargoWord).join(', ')}. Привезите сырьё маршрутом, заказом или через логистический центр.',
              place: i.id,
              weight: 4,
            ),
          );
        }
      }
      // Stock nobody carries away: own places, and places on a route.
      final served =
          i.owned || routes.values.any((r) => r.stops.contains(i.id));
      if (served && i.town == null && !i.spec.stores) {
        for (final c in i.supplies) {
          if ((i.stock[c] ?? 0) >= outputCapOf(i)) {
            out.add(
              MagAdvice(
                MagAdviceKind.stockFull,
                '${i.name}: склад полон',
                '${magCargoWord(c)} ${i.stock[c]} из ${outputCapOf(i)} — выпуск остановлен. Добавьте машину на линию или модернизируйте склад.',
                place: i.id,
                weight: 3,
              ),
            );
            break;
          }
        }
      }
      if (i.spec.stores) {
        final cap = warehouseCapacityOf(i);
        if (storedIn(i) * 10 >= cap * 9) {
          out.add(
            MagAdvice(
              MagAdviceKind.warehouseFull,
              '${i.name} почти полон',
              'Занято ${storedIn(i)} из $cap. Расширьте склад или включите распределение излишков.',
              place: i.id,
              weight: 2,
            ),
          );
        }
      }
      if (i.kind == MagIndustryKind.logisticsCenter) {
        final why = centerIdle(i);
        if (why != null) {
          out.add(
            MagAdvice(
              MagAdviceKind.centerIdle,
              '${i.name} не работает',
              why,
              place: i.id,
              weight: 4,
            ),
          );
        }
      }
    }
    for (final v in vehicles.values) {
      final idle =
          !v.auto &&
          v.routeId == null &&
          v.orderId == null &&
          (v.state == MagVehicleState.garage ||
              v.state == MagVehicleState.idle);
      if (idle) {
        out.add(
          MagAdvice(
            MagAdviceKind.idleVehicle,
            '${v.name} простаивает',
            'Без маршрута и заказа, а содержание ${upkeepOf(v)} кр в день идёт. Поставьте на маршрут, в автопарк или продайте.',
            vehicle: v.id,
            weight: 3,
          ),
        );
      }
    }
    for (final v in vehicles.values) {
      if (v.spec.rail && v.yields >= 2) {
        out.add(
          MagAdvice(
            MagAdviceKind.trainsBlocked,
            '${v.name} уступает путь встречным',
            'Уже ${v.yields} раз: на одной колее поезда мешают друг другу. Проложите второй путь или второй перрон — они разъедутся.',
            vehicle: v.id,
            weight: 4,
          ),
        );
      }
    }
    for (final r in routes.values) {
      if (r.costs > 300 && r.costs > r.income) {
        out.add(
          MagAdvice(
            MagAdviceKind.lossRoute,
            '«${r.name}» в убытке',
            'Доход ${magAmount(r.income)}, расходы машин ${magAmount(r.costs)}. Проверьте груз и расстояние или уберите лишние машины.',
            route: r.id,
            weight: 5,
          ),
        );
      }
      final empty = r.emptyShare;
      if (empty != null && r.cells >= 200 && empty > .6) {
        out.add(
          MagAdvice(
            MagAdviceKind.emptyRoute,
            '«${r.name}»: много порожнего пробега',
            '${(empty * 100).round()}% пути без груза. Добавьте остановку с грузом в обратную сторону.',
            route: r.id,
            weight: 2,
          ),
        );
      }
    }
    for (final i in cities) {
      final c = weeklyDemand(i);
      if (c == null || accessCells(i).isEmpty) continue;
      final source = map.industries.where(
        (s) =>
            s.town == null &&
            !s.spec.stores &&
            s.supplies.contains(c) &&
            availableOf(s, c) >= 20,
      );
      if (source.isEmpty) continue;
      out.add(
        MagAdvice(
          MagAdviceKind.cityDemand,
          '${i.name} платит +${(MagTowns.weeklyBonus * 100).round()}% за ${magCargoWord(c)}',
          'Спрос недели, ещё $weekDaysLeft дн. Груз есть: ${source.first.name} (${availableOf(source.first, c)}). Это оценка, а не обещание прибыли.',
          place: i.id,
          weight: 1,
        ),
      );
    }
    out.sort((a, b) => b.weight.compareTo(a.weight));
    return out;
  }

  /// Places with a problem (for the marks on the map).
  Set<int> get problemPlaces => {
    for (final a in advice)
      if (a.place != null && a.kind != MagAdviceKind.cityDemand) a.place!,
  };
}

/// «1 234» — credits in advice texts.
String magAmount(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '−' : '');
  for (var k = 0; k < s.length; k++) {
    if (k > 0 && (s.length - k) % 3 == 0) b.write(' ');
    b.write(s[k]);
  }
  return b.toString();
}

/// A cargo's word for texts written by the simulation.
String magCargoWord(MagCargo c) =>
    MagEconomy.resource(c.name)?.name.toLowerCase() ?? c.name;
