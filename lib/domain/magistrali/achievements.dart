/// Achievements of a company (META-02, 1.87): each pays once when its
/// goal is met; progress comes from the real state of the world (see
/// `MagWorldMeta.achievementProgress`).
library;

class MagAchievement {
  const MagAchievement(this.id, this.title, this.text, this.goal, this.reward);
  final String id, title, text;
  final int goal, reward;
}

abstract final class MagAchievements {
  static MagAchievement? byId(String id) =>
      all.where((a) => a.id == id).firstOrNull;

  static const all = [
    MagAchievement(
      'roads50',
      'Дорожник',
      'Постройте 50 клеток дорог',
      50,
      1500,
    ),
    MagAchievement(
      'roads300',
      'Строитель магистралей',
      'Постройте 300 клеток дорог',
      300,
      8000,
    ),
    MagAchievement('bridge', 'Через реку', 'Постройте мост', 1, 2000),
    MagAchievement('tunnel', 'Сквозь горы', 'Постройте тоннель', 1, 2000),
    MagAchievement(
      'trips100',
      'Сотня рейсов',
      'Сделайте 100 доставок',
      100,
      2500,
    ),
    MagAchievement(
      'trips1000',
      'Тысяча рейсов',
      'Сделайте 1000 доставок',
      1000,
      15000,
    ),
    MagAchievement('fleet5', 'Свой автопарк', 'Соберите 5 машин', 5, 2000),
    MagAchievement(
      'fleet20',
      'Транспортная компания',
      'Соберите 20 машин',
      20,
      10000,
    ),
    MagAchievement(
      'routes5',
      'Сеть маршрутов',
      'Откройте 5 маршрутов',
      5,
      2500,
    ),
    MagAchievement(
      'earn100k',
      'Первые сто тысяч',
      'Заработайте 100 000 кр',
      100000,
      5000,
    ),
    MagAchievement(
      'earn1m',
      'Миллионер',
      'Заработайте 1 000 000 кр',
      1000000,
      40000,
    ),
    MagAchievement(
      'level10',
      'Крепкая компания',
      'Достигните 10 уровня',
      10,
      6000,
    ),
    MagAchievement(
      'level20',
      'Транспортная империя',
      'Достигните 20 уровня',
      20,
      25000,
    ),
    MagAchievement(
      'owner3',
      'Промышленник',
      'Владейте 3 предприятиями',
      3,
      6000,
    ),
    MagAchievement(
      'city',
      'Город вырос',
      'Помогите поселению стать городом',
      1,
      5000,
    ),
    MagAchievement(
      'rail',
      'Стальной путь',
      'Проложите 20 клеток рельсов',
      20,
      6000,
    ),
    MagAchievement('ship', 'Капитан', 'Купите судно', 1, 4000),
    MagAchievement(
      'people500',
      'Пассажирский перевозчик',
      'Перевезите 500 пассажиров и работников',
      500,
      6000,
    ),
    MagAchievement('tech15', 'Изобретатель', 'Изучите 15 технологий', 15, 8000),
    MagAchievement('mega', 'Великая стройка', 'Завершите мегапроект', 1, 20000),
  ];
}
