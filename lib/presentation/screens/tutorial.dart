import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:flutter/services.dart';

import '../widgets/finora_orb.dart';
import '../widgets/motion.dart';
import '../widgets/voice_orb.dart';
import 'onboarding.dart';
import '../i18n.dart';
import '../l10n_widgets.dart';
import '../controller.dart';
import '../widgets/common.dart' show showError;

/// A short tour of the whole app (Finance 1.25), offered at the end of the
/// welcome screens and kept in Settings. Swipe or «Далее»; «Пропустить» is
/// always at the top. Each page shows a small drawing of the thing itself.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  /// Number of pages, the last one being «Готово».
  static int get pageCount => _pages.length;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _Page {
  const _Page({
    required this.icon,
    required this.color,
    required this.eyebrow,
    required this.title,
    required this.text,
    required this.tips,
    required this.picture,
  });
  final IconData icon;
  final Color Function(bool dark) color;
  final String eyebrow, title, text;
  final List<(IconData, String)> tips;
  final Widget Function(BuildContext context, bool dark) picture;
}

final _pages = <_Page>[
  _Page(
    icon: Icons.space_dashboard_rounded,
    color: AppleUi.blue,
    eyebrow: 'Главная',
    title: 'Все деньги на одном экране',
    text:
        'Баланс всех счетов, доходы и расходы за месяц, мечты, подписки '
        'и бюджеты.',
    tips: [
      (
        Icons.pan_tool_alt_outlined,
        'Удерживайте блок и перетащите — порядок ваш',
      ),
      (
        Icons.touch_app_outlined,
        'Нажмите на доходы или расходы — откроется список',
      ),
      (
        Icons.donut_large_rounded,
        'В «Обзоре месяца» нажмите на часть круга — увидите долю категории',
      ),
    ],
    picture: (context, dark) => const _DashboardPicture(),
  ),
  _Page(
    icon: Icons.mic_rounded,
    color: AppleUi.indigo,
    eyebrow: 'Финора',
    title: 'Знакомьтесь: Финора',
    text:
        'Кругляш внизу — ваш финансовый ассистент. Нажмите: Финора '
        'обрадуется и выслушает. Назовите магазин и сумму — категория '
        'подберётся сама.',
    tips: [
      (
        Icons.record_voice_over_outlined,
        '«Пятёрочка 450», «зарплата 90 тысяч»',
      ),
      (
        Icons.translate_rounded,
        'Сервисы можно называть по-русски: «чат гпт», «нетфликс»',
      ),
      (Icons.front_hand_outlined, 'Удержание кругляша — колесо действий'),

      (
        Icons.record_voice_over_rounded,
        'Скажите «Финора» — откликнется, пока приложение открыто',
      ),
      (
        Icons.power_settings_new_rounded,
        'По кнопке питания — сделайте Финору помощником телефона',
      ),
    ],
    picture: (context, dark) => const _VoicePicture(),
  ),
  _Page(
    icon: Icons.emoji_emotions_rounded,
    color: AppleUi.orange,
    eyebrow: 'Эмоции',
    title: 'Финора живая',
    text:
        'Она радуется зарплате, удивляется большим тратам и сердится, '
        'когда бюджет превышен или платёж просрочен. Без касаний — засыпает.',
    tips: [
      (Icons.vibration_rounded, 'Каждое нажатие и реакция — с лёгкой отдачей'),
      (Icons.touch_app_outlined, 'Нажмите на Финору — она обрадуется'),
    ],
    picture: (context, dark) => const _MoodsPicture(),
  ),
  _Page(
    icon: Icons.notifications_active_rounded,
    color: AppleUi.green,
    eyebrow: 'Платежи',
    title: 'Сначала — подтверждение',
    text:
        'Подписка или обязательный платёж попадают в расходы только после '
        '«Оплачено». В день платежа Финора сама спросит.',
    tips: [
      (Icons.schedule_rounded, '«Напомнить позже» — спросит через пару часов'),
      (Icons.skip_next_rounded, '«В этот раз не платить» — без записи'),
    ],
    picture: (context, dark) => const _PaymentPicture(),
  ),
  _Page(
    icon: Icons.widgets_rounded,
    color: AppleUi.purple,
    eyebrow: 'Виджеты и шторка',
    title: 'Финора на рабочем столе',
    text:
        'Виджеты с балансом, кнопками и ближайшими платежами. Плитка «Финора» '
        'в шторке открывает голос одним нажатием.',
    tips: [
      (
        Icons.add_to_home_screen_rounded,
        'Рабочий стол → удерживайте → «Виджеты» → Finora',
      ),
      (Icons.edit_rounded, 'Шторка → карандаш → перетащите плитку «Финора»'),
    ],
    picture: (context, dark) => const _WidgetsPicture(),
  ),
  _Page(
    icon: Icons.assistant_navigation,
    color: AppleUi.purple,
    eyebrow: 'Команды',
    title: 'Управляйте голосом',
    text: 'Финора понимает просьбы: показать, открыть, перекрасить.',
    tips: [
      (
        Icons.calendar_month_outlined,
        '«Покажи доход за год», «расходы за прошлый месяц»',
      ),
      (Icons.local_cafe_outlined, '«Сколько я потратил на кафе в мае»'),
      (Icons.dark_mode_outlined, '«Сделай тёмную тему», «открой настройки»'),
    ],
    picture: (context, dark) => const _Chat([
      ('Покажи расходы за июнь', 'Расходы · июнь — 42 380 ₽'),
      ('Поменяй тему на зелёную', 'Тема: Emerald'),
      ('Открой бюджеты', 'Открываю бюджеты'),
    ]),
  ),
  _Page(
    icon: Icons.record_voice_over_rounded,
    color: AppleUi.green,
    eyebrow: 'Голосовые команды',
    title: 'Что сказать Финоре',
    text:
        'Записать: «Пятёрочка 450», «Т2 695 рублей». Показать: «расходы за '
        'июнь». Платежи: «обязательный платёж кредит 15 000 25 числа», '
        '«подписка Яндекс Плюс 399 в месяц».',
    tips: [
      (Icons.auto_awesome_outlined, 'Мечты: «хочу машину за 2 миллиона»'),
      (Icons.palette_outlined, 'Тема: «поменяй тему на зелёную»'),
      (
        Icons.list_alt_rounded,
        'Полный список — Настройки → Финора → «Голосовые команды»',
      ),
    ],
    picture: (context, dark) => const _Chat([
      ('Т2 695 рублей', 'Записала: Т2 −695 ₽'),
      ('Обязательный платёж кредит 15 000 25 числа', 'Кредит · 25-го'),
    ]),
  ),
  _Page(
    icon: Icons.auto_awesome_rounded,
    color: AppleUi.orange,
    eyebrow: 'Создание голосом',
    title: 'Мечты, счета, подписки',
    text:
        'Скажите, что добавить, — появится сразу, а внизу будет '
        '«Отменить».',
    tips: [
      (
        Icons.account_balance_wallet_outlined,
        '«Добавь карту Сбер с балансом 15 тысяч»',
      ),
      (Icons.event_repeat_outlined, '«Подписка Яндекс Плюс 399 в месяц»'),
      (Icons.pie_chart_outline, '«Бюджет на продукты 20 тысяч»'),
    ],
    picture: (context, dark) => const _DreamPicture(),
  ),
  _Page(
    icon: Icons.document_scanner_rounded,
    color: AppleUi.green,
    eyebrow: 'Скриншоты из банка',
    title: 'Операции со скриншота',
    text:
        'Поделитесь скриншотом из банка или выберите его — операции '
        'распознаются на телефоне, без интернета.',
    tips: [
      (Icons.share_outlined, 'Из галереи: «Поделиться», затем Finora'),
      (
        Icons.swap_horiz_rounded,
        'Переводы между своими счетами — отдельной категорией',
      ),
    ],
    picture: (context, dark) => const _ScanPicture(),
  ),
  _Page(
    icon: Icons.bar_chart_rounded,
    color: AppleUi.blue,
    eyebrow: 'Операции и аналитика',
    title: 'Куда уходят деньги',
    text:
        'Поиск по магазину, фильтры по счёту, категории и сумме. В '
        'аналитике — доли категорий и динамика по месяцам.',
    tips: [
      (Icons.search_rounded, 'Поиск и фильтры — на вкладке «Операции»'),
      (Icons.insights_outlined, 'Нажмите на категорию — увидите все её траты'),
    ],
    picture: (context, dark) => const _AnalyticsPicture(),
  ),
  _Page(
    icon: Icons.grid_view_rounded,
    color: AppleUi.indigo,
    eyebrow: 'Вкладка «Ещё»',
    title: 'Всё для планирования',
    text: 'Счета, мечты, бюджеты, подписки, календарь платежей и семья.',
    tips: [
      (
        Icons.notifications_none_rounded,
        'Напоминания о платежах — по желанию у каждого',
      ),
      (Icons.family_restroom_outlined, 'Участники — чьи это траты'),
      (
        Icons.swipe_left_rounded,
        'Смахните счёт, мечту или подписку влево — удалить',
      ),
    ],
    picture: (context, dark) => const _MorePicture(),
  ),
  _Page(
    icon: Icons.lock_rounded,
    color: AppleUi.green,
    eyebrow: 'Безопасность и данные',
    title: 'Ваши данные — только у вас',
    text:
        'Приложение не ходит в интернет. Вход по PIN или отпечатку, '
        'резервные копии, перенос счетов из другого приложения по '
        'скриншоту.',
    tips: [
      (
        Icons.settings_outlined,
        'Настройки — по разделам: вид, защита, резервные копии',
      ),
      (Icons.swipe_right_alt_rounded, 'Сброс данных подтверждается свайпом'),
      (Icons.school_outlined, 'Обучение можно открыть снова в настройках'),
      (Icons.translate_rounded, 'Язык приложения — на выбор из девяти'),
    ],
    picture: (context, dark) => const _SafePicture(),
  ),
];

class _TutorialScreenState extends State<TutorialScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _last => _page == _pages.length - 1;

  void _go(int page) {
    HapticFeedback.selectionClick();
    if (Motion.reduced(context)) {
      _controller.jumpToPage(page);
    } else {
      _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 460),
        curve: const Cubic(.32, .72, 0, 1),
      );
    }
  }

  void _close() {
    HapticFeedback.lightImpact();
    Navigator.pop(context, true);
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      // The same tour also runs standalone in accessibility tests.
      final c = context.getInheritedWidgetOfExactType<FinanceScope>()?.notifier;
      if (c != null) await c.completeWorldTutorial();
      if (mounted) _close();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppleUi.back(dark),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
              child: Row(
                children: [
                  // Progress like stories: one segment per page.
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: i <= _page
                                    ? _pages[_page].color(dark)
                                    : AppleUi.grouped(dark),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    key: const ValueKey('tutorial-skip'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppleUi.secondary(dark),
                    ),
                    onPressed: _close,
                    child: Text(_last ? 'Закрыть' : 'Пропустить'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (p) => setState(() => _page = p),
                itemBuilder: (context, i) => _PageView(
                  key: ValueKey('tutorial-page-$i'),
                  page: _pages[i],
                  index: i,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
              child: Row(
                children: [
                  AnimatedOpacity(
                    opacity: _page == 0 ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: IconButton.filledTonal(
                      key: const ValueKey('tutorial-back'),
                      tooltip: 'Назад',
                      style: IconButton.styleFrom(
                        backgroundColor: AppleUi.grouped(dark),
                        foregroundColor: AppleUi.label(dark),
                        fixedSize: const Size(52, 52),
                      ),
                      onPressed: _page == 0 ? null : () => _go(_page - 1),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppleButton(
                      key: ValueKey(_last ? 'tutorial-done' : 'tutorial-next'),
                      label: _last ? 'Начать пользоваться' : 'Далее',
                      onPressed: _finishing
                          ? null
                          : _last
                          ? _finish
                          : () => _go(_page + 1),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({super.key, required this.page, required this.index});
  final _Page page;
  final int index;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = page.color(dark);
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The drawing on a soft panel.
              Container(
                height: 240,
                decoration: BoxDecoration(
                  color: AppleUi.grouped(dark),
                  borderRadius: BorderRadius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(18),
                // Drawn for a 320-wide panel and scaled down to fit small
                // phones and large text.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 320,
                    // An illustration: drawn at one size and scaled as a
                    // whole, so large system text does not break it.
                    child: MediaQuery.withNoTextScaling(
                      child: Center(child: page.picture(context, dark)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(page.icon, color: Colors.white, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${tr(page.eyebrow).toUpperCase()} · ${index + 1} из '
                      '${_pages.length}',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: .6,
                        fontWeight: FontWeight.w600,
                        color: AppleUi.secondary(dark),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                page.title,
                style: TextStyle(
                  fontSize: 28,
                  height: 1.12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                  color: AppleUi.label(dark),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                page.text,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.38,
                  color: AppleUi.secondary(dark),
                ),
              ),
              if (page.tips.isNotEmpty) ...[
                const SizedBox(height: 18),
                for (final (icon, tip) in page.tips)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 20, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tip,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.3,
                              color: AppleUi.label(dark),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Drawings ──────────────────────────────────────────────────────────────

/// A rounded white/black card used inside the drawings.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.width, this.padding});
  final Widget child;
  final double? width;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: dark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );
  }
}

TextStyle _small(bool dark) =>
    TextStyle(fontSize: 11, color: AppleUi.secondary(dark));
TextStyle _strong(bool dark, [double size = 15]) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w700,
  color: AppleUi.label(dark),
);

class _DashboardPicture extends StatelessWidget {
  const _DashboardPicture();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget tile(String label, String value, Color color, IconData icon) =>
        Expanded(
          child: _Card(
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: _small(dark)),
                      Text(value, style: _strong(dark, 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return SizedBox(
      width: 270,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Card(
            width: 270,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Баланс', style: _small(dark)),
                const SizedBox(height: 2),
                Text('184 250 ₽', style: _strong(dark, 26)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              tile(
                'Доходы',
                '96 000 ₽',
                AppleUi.green(dark),
                Icons.south_west_rounded,
              ),
              const SizedBox(width: 10),
              tile(
                'Расходы',
                '42 380 ₽',
                AppleUi.orange(dark),
                Icons.north_east_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Transform.rotate(
            angle: -.03,
            child: _Card(
              width: 250,
              child: Row(
                children: [
                  Icon(
                    Icons.drag_indicator_rounded,
                    size: 18,
                    color: AppleUi.blue(dark),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Мечты', style: _strong(dark, 13))),
                  Flexible(
                    child: Text(
                      'перетащите',
                      style: _small(dark),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A speech bubble from the person (blue) or an answer (gray).
class _Bubble extends StatelessWidget {
  const _Bubble(this.text, {this.mine = true});
  final String text;
  final bool mine;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 230),
        decoration: BoxDecoration(
          color: mine
              ? AppleUi.blue(dark)
              : dark
              ? const Color(0xFF2C2C2E)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mine) ...[
              const Icon(Icons.mic_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                mine ? '«$text»' : text,
                style: TextStyle(
                  fontSize: 13,
                  color: mine ? Colors.white : AppleUi.label(dark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoicePicture extends StatelessWidget {
  const _VoicePicture();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Bubble('Пятёрочка 450 рублей'),
        const SizedBox(height: 10),
        VoiceOrb(size: 76, onTap: () {}, onLongPress: () {}),
        const SizedBox(height: 12),
        _Card(
          width: 230,
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppleUi.green(dark),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shopping_basket_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Пятёрочка', style: _strong(dark, 13)),
                    Text('Продукты', style: _small(dark)),
                  ],
                ),
              ),
              Text('−450 ₽', style: _strong(dark, 13)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chat extends StatelessWidget {
  const _Chat(this.lines);
  final List<(String, String)> lines;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (said, answer) in lines) ...[
          _Bubble(said),
          _Bubble(answer, mine: false),
          const SizedBox(height: 4),
        ],
      ],
    ),
  );
}

class _DreamPicture extends StatelessWidget {
  const _DreamPicture();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Bubble('Хочу машину за 2 млн'),
          const SizedBox(height: 10),
          _Card(
            width: 250,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.directions_car_rounded,
                      size: 18,
                      color: AppleUi.orange(dark),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Машина', style: _strong(dark, 14))),
                    Text('мечта', style: _small(dark)),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: .18,
                    minHeight: 7,
                    color: AppleUi.orange(dark),
                    backgroundColor: AppleUi.grouped(dark),
                  ),
                ),
                const SizedBox(height: 8),
                Text('360 000 из 2 000 000 ₽', style: _small(dark)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF3A3A3C) : const Color(0xFF323232),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(
                  child: Text(
                    'Мечта добавлена',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  'Отменить',
                  style: TextStyle(
                    color: AppleUi.blue(true),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanPicture extends StatelessWidget {
  const _ScanPicture();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget row(String store, String sum) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppleUi.grouped(dark),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(store, style: _small(dark))),
          Text(sum, style: _small(dark)),
        ],
      ),
    );
    Widget chip(String category, Color color) => Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        category,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Card(
          width: 140,
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Выписка', style: _strong(dark, 12)),
              const SizedBox(height: 6),
              row('Пятёрочка', '−812'),
              row('Whoosh', '−164'),
              row('Аптека', '−390'),
              row('Себе', '−5 000'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Icon(Icons.arrow_forward_rounded, color: AppleUi.green(dark)),
        ),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              chip('Продукты', AppleUi.green(dark)),
              chip('Транспорт', AppleUi.blue(dark)),
              chip('Здоровье', AppleUi.purple(dark)),
              chip('Перевод', AppleUi.orange(dark)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnalyticsPicture extends StatelessWidget {
  const _AnalyticsPicture();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final parts = [
      (.38, AppleUi.green(dark), 'Продукты'),
      (.24, AppleUi.blue(dark), 'Транспорт'),
      (.2, AppleUi.orange(dark), 'Кафе'),
      (.18, AppleUi.purple(dark), 'Другое'),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 130,
          child: CustomPaint(
            painter: _Donut([for (final p in parts) (p.$1, p.$2)]),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Ноябрь', style: _small(dark)),
                  Text('42 380 ₽', style: _strong(dark, 15)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (share, color, name) in parts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '$name  ${(share * 100).round()}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppleUi.label(dark),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Donut extends CustomPainter {
  const _Donut(this.parts);
  final List<(double, Color)> parts;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const stroke = 16.0;
    var start = -1.5708;
    for (final (share, color) in parts) {
      final sweep = share * 6.2832;
      canvas.drawArc(
        rect.deflate(stroke / 2),
        start + .04,
        sweep - .08,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_Donut old) => false;
}

class _MorePicture extends StatelessWidget {
  const _MorePicture();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final items = [
      (Icons.account_balance_wallet_rounded, 'Счета', AppleUi.blue(dark)),
      (Icons.star_rounded, 'Мечты', AppleUi.orange(dark)),
      (Icons.pie_chart_rounded, 'Бюджеты', AppleUi.green(dark)),
      (Icons.event_repeat_rounded, 'Подписки', AppleUi.purple(dark)),
      (Icons.calendar_month_rounded, 'Календарь', AppleUi.indigo(dark)),
      (Icons.people_alt_rounded, 'Семья', AppleUi.blue(dark)),
    ];
    return SizedBox(
      width: 280,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          for (final (icon, label, color) in items)
            _Card(
              width: 84,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: Colors.white, size: 19),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: _small(dark)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SafePicture extends StatelessWidget {
  const _SafePicture();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget row(IconData icon, String text, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Flexible(child: Text(text, style: _strong(dark, 13))),
        ],
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: AppleUi.green(dark),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(
            Icons.fingerprint_rounded,
            size: 50,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 18),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row(Icons.wifi_off_rounded, 'Без интернета', AppleUi.blue(dark)),
              row(
                Icons.save_alt_rounded,
                'Резервная копия',
                AppleUi.orange(dark),
              ),
              row(
                Icons.move_down_rounded,
                'Перенос счетов',
                AppleUi.purple(dark),
              ),
              row(
                Icons.restart_alt_rounded,
                'Сброс в настройках',
                AppleUi.indigo(dark),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoodsPicture extends StatelessWidget {
  const _MoodsPicture();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const moods = [
      (FinoraMood.happy, 'Зарплата'),
      (FinoraMood.surprised, '−12 000 ₽'),
      (FinoraMood.angry, 'Лимит'),
      (FinoraMood.done, 'Записала'),
      (FinoraMood.attention, 'Платёж'),
      (FinoraMood.sleep, 'Тишина'),
    ];
    return Wrap(
      spacing: 22,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        for (final (mood, label) in moods)
          SizedBox(
            width: 72,
            child: Column(
              children: [
                FinoraMark(size: 48, mood: mood),
                const SizedBox(height: 8),
                Text(label, style: _small(dark)),
              ],
            ),
          ),
      ],
    );
  }
}

class _PaymentPicture extends StatelessWidget {
  const _PaymentPicture();
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _Card(
      width: 240,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FinoraMark(size: 46, mood: FinoraMood.attention),
          const SizedBox(height: 8),
          Text('Сегодня списание подписки', style: _strong(dark, 13)),
          const SizedBox(height: 4),
          Text('Netflix · 799 ₽', style: _small(dark)),
          const SizedBox(height: 10),
          Container(
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppleUi.blue(dark),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Оплачено',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetsPicture extends StatelessWidget {
  const _WidgetsPicture();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 120,
          height: 120,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0E2A33), Color(0xFF123B44)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FinoraMark(size: 52, mood: FinoraMood.happy),
              SizedBox(height: 6),
              Text(
                '184 250 ₽',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Container(
          width: 120,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: Color(0xFF3FE0C2),
                child: Icon(
                  Icons.mic_rounded,
                  size: 17,
                  color: Color(0xFF0A2730),
                ),
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Финора',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
