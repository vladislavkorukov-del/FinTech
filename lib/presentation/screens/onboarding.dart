import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models.dart';
import '../controller.dart';
import '../widgets/motion.dart';
import 'account_import_screen.dart';
import 'tutorial.dart';

/// Welcome screens (Finance 1.21; Apple style since 1.22): on the first launch
/// of a new install and after «Сбросить всё». Pure black or white, large
/// bold titles, an icon tile per step, the Apple blue button, an inset
/// grouped list for choices and a drawn check at the end.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// iOS system colors.
abstract final class AppleUi {
  static Color blue(bool dark) =>
      dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
  static Color green(bool dark) =>
      dark ? const Color(0xFF30D158) : const Color(0xFF34C759);
  static Color orange(bool dark) =>
      dark ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500);
  static Color purple(bool dark) =>
      dark ? const Color(0xFFBF5AF2) : const Color(0xFFAF52DE);
  static Color indigo(bool dark) =>
      dark ? const Color(0xFF5E5CE6) : const Color(0xFF5856D6);
  static Color back(bool dark) => dark ? Colors.black : Colors.white;
  static Color grouped(bool dark) =>
      dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
  static Color label(bool dark) => dark ? Colors.white : Colors.black;
  static Color secondary(bool dark) =>
      dark ? const Color(0x99EBEBF5) : const Color(0x993C3C43);
  static Color separator(bool dark) =>
      dark ? const Color(0x5C545458) : const Color(0x4A3C3C43);
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  final _name = TextEditingController();
  int _page = 0;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // After a reset the name from last time is already filled in.
    if (_name.text.isEmpty) {
      _name.text = FinanceScope.of(context).data.preferences.userName;
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  void _go(int page) {
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() => _page = page);
    if (Motion.reduced(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 520),
        curve: const Cubic(.32, .72, 0, 1), // iOS sheet curve
      );
    }
  }

  Future<void> _saveName() async {
    final c = FinanceScope.of(context);
    final name = _name.text.trim();
    await c.mutate(
      (d) => d.copyWith(
        preferences: d.preferences.copyWith(userName: name),
        members: [
          for (final m in d.members)
            m.id == 'me' && name.isNotEmpty ? Member(id: 'me', name: name) : m,
        ],
      ),
    );
  }

  Future<void> _source(String choice) async {
    if (_busy) return;
    final c = FinanceScope.of(context);
    setState(() => _busy = true);
    try {
      if (choice == 'example') {
        // After a reset the example has to be loaded again.
        if (!c.data.demo && c.data.entries.isEmpty && c.data.accounts.isEmpty) {
          await c.loadDemo();
        }
      } else if (c.data.demo) {
        // Start clean: the demo ledger goes, the name and look stay.
        await c.resetAll();
      }
      if (choice == 'import' && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const AccountImportScreen()),
        );
      }
      if (mounted) _go(4);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// With [tour], the short app tour (1.25) comes first; it can be left
  /// at any page.
  Future<void> _finish({bool tour = false}) async {
    if (_busy) return;
    final c = FinanceScope.of(context);
    HapticFeedback.mediumImpact();
    // Close the keyboard before the main screen appears (1.22.1).
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (tour && mounted) {
      setState(() => _busy = true);
      try {
        await Navigator.push(
          context,
          MaterialPageRoute<bool>(
            fullscreenDialog: true,
            builder: (_) => const TutorialScreen(),
          ),
        );
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    await c.mutate(
      (d) => d.copyWith(preferences: d.preferences.copyWith(onboarded: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = c.data.preferences.userName;
    return Scaffold(
      backgroundColor: AppleUi.back(dark),
      body: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Hello(onStart: () => _go(1)),
                _Step(
                  icon: Icons.person_rounded,
                  tile: AppleUi.blue(dark),
                  title: 'Как вас зовут?',
                  subtitle: 'Так Finance будет к вам обращаться.',
                  primary: 'Продолжить',
                  onPrimary: _name.text.trim().isEmpty
                      ? null
                      : () async {
                          await _saveName();
                          if (mounted) _go(2);
                        },
                  secondary: 'Пропустить',
                  onSecondary: () => _go(2),
                  child: _NameField(
                    controller: _name,
                    onChanged: () => setState(() {}),
                    onSubmitted: () async {
                      if (_name.text.trim().isEmpty) return;
                      await _saveName();
                      if (mounted) _go(2);
                    },
                  ),
                ),
                _Step(
                  icon: Icons.contrast_rounded,
                  tile: AppleUi.indigo(dark),
                  title: 'Светлое или тёмное?',
                  subtitle: 'Это можно поменять в настройках.',
                  primary: 'Продолжить',
                  onPrimary: () => _go(3),
                  child: _Appearance(
                    value: c.data.preferences.theme,
                    onChanged: (theme) => c.preferences(
                      c.data.preferences.copyWith(theme: theme),
                    ),
                  ),
                ),
                _Step(
                  icon: Icons.swap_horiz_rounded,
                  tile: AppleUi.green(dark),
                  title: 'Перенести данные?',
                  subtitle:
                      'Счета из другой домашней бухгалтерии можно перенести '
                      'по скриншоту — с названиями и остатками.',
                  child: _Group(
                    children: [
                      _Choice(
                        key: const ValueKey('onboarding-import'),
                        icon: Icons.photo_library_rounded,
                        tile: AppleUi.green(dark),
                        title: 'Перенести счета со скриншота',
                        subtitle: 'Дзен-мани, CoinKeeper, Monefy, банк',
                        onTap: _busy ? null : () => _source('import'),
                      ),
                      _Choice(
                        key: const ValueKey('onboarding-clean'),
                        icon: Icons.auto_awesome_rounded,
                        tile: AppleUi.blue(dark),
                        title: 'Начать с чистого листа',
                        subtitle: 'Добавите счета сами',
                        onTap: _busy ? null : () => _source('clean'),
                      ),
                      _Choice(
                        key: const ValueKey('onboarding-example'),
                        icon: Icons.visibility_rounded,
                        tile: AppleUi.orange(dark),
                        title: 'Посмотреть на примере',
                        subtitle: 'Демо-данные, потом их можно очистить',
                        onTap: _busy ? null : () => _source('example'),
                      ),
                    ],
                  ),
                ),
                _Done(
                  name: name,
                  visible: _page == 4,
                  onTour: () => _finish(tour: true),
                  onFinish: _finish,
                ),
              ],
            ),
            if (_page > 0 && _page < 4)
              Positioned(
                left: 2,
                top: 2,
                child: TextButton.icon(
                  key: const ValueKey('onboarding-back'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppleUi.blue(dark),
                  ),
                  onPressed: () => _go(_page - 1),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  label: const Text('Назад'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// «Привет» in many languages, its letters filled with a slowly drifting
/// gradient, as on the iPhone welcome screen.
class _Hello extends StatefulWidget {
  const _Hello({required this.onStart});
  final VoidCallback onStart;
  @override
  State<_Hello> createState() => _HelloState();
}

class _HelloState extends State<_Hello> with SingleTickerProviderStateMixin {
  static const _words = [
    'Привет',
    'Hello',
    'Hola',
    'Bonjour',
    'Ciao',
    'Hallo',
    'Merhaba',
    'Сәлем',
    'Olá',
    'こんにちは',
    '你好',
    'Привет',
  ];
  int _i = 0;
  Timer? _timer, _rest;
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    if (Motion.ambient(context)) {
      if (!_shine.isAnimating) _shine.repeat();
      _timer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
        if (!mounted) return;
        setState(() => _i = (_i + 1) % _words.length);
        // One round, then it rests on «Привет».
        if (_i == _words.length - 1) {
          _timer?.cancel();
          _rest = Timer(const Duration(seconds: 3), () {
            if (mounted) _shine.stop();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rest?.cancel();
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = [
      AppleUi.blue(dark),
      AppleUi.purple(dark),
      const Color(0xFFFF375F),
      AppleUi.orange(dark),
      AppleUi.green(dark),
      AppleUi.blue(dark),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 28),
      child: Column(
        children: [
          const Spacer(flex: 5),
          SizedBox(
            height: 120,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 900),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, .08),
                    end: Offset.zero,
                  ).animate(a),
                  child: child,
                ),
              ),
              child: AnimatedBuilder(
                key: ValueKey(_i),
                animation: _shine,
                builder: (context, child) => ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (rect) {
                    final shift = _shine.value * 2;
                    return LinearGradient(
                      begin: Alignment(-1 - shift, -.3),
                      end: Alignment(3 - shift, .3),
                      colors: colors,
                      tileMode: TileMode.mirror,
                    ).createShader(rect);
                  },
                  child: child,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _words[_i],
                    style: const TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -2.5,
                      height: 1,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Finance',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppleUi.label(dark),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ваши деньги — спокойно и под контролем',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppleUi.secondary(dark)),
          ),
          const Spacer(flex: 6),
          AppleButton(
            key: const ValueKey('onboarding-start'),
            label: 'Начать',
            onPressed: widget.onStart,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// One setup step: an icon tile, a large bold title, a line of explanation,
/// the content, and the main button pinned to the bottom.
class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.tile,
    required this.title,
    required this.subtitle,
    required this.child,
    this.primary,
    this.onPrimary,
    this.secondary,
    this.onSecondary,
  });
  final IconData icon;
  final Color tile;
  final String title, subtitle;
  final Widget child;
  final String? primary, secondary;
  final VoidCallback? onPrimary, onSecondary;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: tile,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white, size: 36),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -.8,
              height: 1.1,
              color: AppleUi.label(dark),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.35,
              color: AppleUi.secondary(dark),
            ),
          ),
          const SizedBox(height: 32),
          Expanded(child: SingleChildScrollView(child: child)),
          if (primary != null)
            AppleButton(
              key: ValueKey('onboarding-$primary'),
              label: primary!,
              onPressed: onPrimary,
            ),
          if (secondary != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppleUi.blue(dark)),
              onPressed: onSecondary,
              child: Text(secondary!),
            ),
        ],
      ),
    );
  }
}

/// The Apple blue, full-width, 14-radius button.
class AppleButton extends StatelessWidget {
  const AppleButton({super.key, required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // At least 52 high; taller with large system text instead of clipping.
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: double.infinity,
        minHeight: 52,
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppleUi.blue(dark),
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppleUi.grouped(dark),
          disabledForegroundColor: AppleUi.secondary(dark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          // 1.22.1: no vertical padding and a tight line, so the label is
          // never clipped by the fixed height (the theme style is tall).
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          minimumSize: const Size(double.infinity, 52),
          textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// A large borderless field on the grouped background, centered.
class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
  });
  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: AppleUi.grouped(dark),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        key: const ValueKey('onboarding-name'),
        controller: controller,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.words,
        cursorColor: AppleUi.blue(dark),
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: AppleUi.label(dark),
        ),
        decoration: InputDecoration(
          hintText: 'Имя',
          hintStyle: TextStyle(color: AppleUi.secondary(dark)),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
        onChanged: (_) => onChanged(),
        onSubmitted: (_) => onSubmitted(),
      ),
    );
  }
}

/// Light / dark with phone previews and a round check under each, as in
/// «Экран и яркость»; «Как в системе» below.
class _Appearance extends StatelessWidget {
  const _Appearance({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final blue = AppleUi.blue(dark);
    Widget option(String id, String label, Color back, Color ink) {
      final on = value == id;
      return Expanded(
        child: GestureDetector(
          key: ValueKey('onboarding-theme-$id'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(id);
          },
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 96,
                height: 190,
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
                decoration: BoxDecoration(
                  color: back,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: on ? blue : AppleUi.separator(dark),
                    width: on ? 3 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: 46,
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: .8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final w in [1.0, .7, 1.0, .55])
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        height: 18,
                        width: 70 * w,
                        decoration: BoxDecoration(
                          color: ink.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppleUi.label(dark),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? blue : Colors.transparent,
                  border: Border.all(
                    color: on ? blue : AppleUi.separator(dark),
                    width: 1.5,
                  ),
                ),
                child: on
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            option('light', 'Светлое', Colors.white, Colors.black),
            option('dark', 'Тёмное', const Color(0xFF1C1C1E), Colors.white),
          ],
        ),
        const SizedBox(height: 22),
        _Group(
          children: [
            _Toggle(
              key: const ValueKey('onboarding-theme-system'),
              title: 'Как в системе',
              on: value == 'system',
              onChanged: (on) =>
                  onChanged(on ? 'system' : (dark ? 'dark' : 'light')),
            ),
          ],
        ),
      ],
    );
  }
}

/// An inset grouped list with hairline separators, iOS Settings style.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: AppleUi.grouped(dark),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: Divider(
                    height: .5,
                    thickness: .5,
                    color: AppleUi.separator(dark),
                  ),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// A row with an icon in a colored rounded square and a chevron.
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.icon,
    required this.tile,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final Color tile;
  final String title, subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tile,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppleUi.label(dark),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppleUi.secondary(dark),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppleUi.separator(dark)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row with an iOS-like switch.
class _Toggle extends StatelessWidget {
  const _Toggle({
    super.key,
    required this.title,
    required this.on,
    required this.onChanged,
  });
  final String title;
  final bool on;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 16, color: AppleUi.label(dark)),
            ),
          ),
          Switch(
            value: on,
            activeThumbColor: Colors.white,
            activeTrackColor: AppleUi.green(dark),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: dark
                ? const Color(0xFF39393D)
                : const Color(0xFFE9E9EA),
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// «Всё готово»: a check drawn stroke by stroke, then the way into the app.
class _Done extends StatelessWidget {
  const _Done({
    required this.name,
    required this.visible,
    required this.onTour,
    required this.onFinish,
  });
  final String name;
  final bool visible;
  final VoidCallback onTour, onFinish;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 28),
      child: Column(
        children: [
          const Spacer(flex: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: visible ? 0 : 1, end: 1),
            duration: Motion.reduced(context)
                ? Duration.zero
                : const Duration(milliseconds: 1100),
            curve: Curves.easeInOutCubic,
            builder: (_, t, _) => CustomPaint(
              size: const Size.square(110),
              painter: _CheckPainter(t: t, color: AppleUi.green(dark)),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            name.isEmpty ? 'Всё готово!' : 'Всё готово, $name!',
            key: const ValueKey('onboarding-done'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -.8,
              color: AppleUi.label(dark),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Хотите короткое знакомство с приложением? Восемь карточек — '
            'около минуты. Его можно пропустить в любой момент.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.35,
              color: AppleUi.secondary(dark),
            ),
          ),
          const Spacer(flex: 5),
          AppleButton(
            key: const ValueKey('onboarding-tour'),
            label: 'Показать, что умеет Finance',
            onPressed: onTour,
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const ValueKey('onboarding-finish'),
            style: TextButton.styleFrom(
              foregroundColor: AppleUi.blue(dark),
              minimumSize: const Size(double.infinity, 44),
            ),
            onPressed: onFinish,
            child: const Text('Пропустить обучение'),
          ),
        ],
      ),
    );
  }
}

/// A circle drawn first, then the tick, like a payment confirmation.
class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.t, required this.color});
  final double t;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final circle = (t / .6).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 4),
      -math.pi / 2,
      2 * math.pi * circle,
      false,
      stroke,
    );
    final tick = ((t - .55) / .45).clamp(0.0, 1.0);
    if (tick <= 0) return;
    final a = Offset(size.width * .29, size.height * .52);
    final b = Offset(size.width * .44, size.height * .67);
    final d = Offset(size.width * .72, size.height * .37);
    final path = Path()..moveTo(a.dx, a.dy);
    if (tick < .4) {
      final p = Offset.lerp(a, b, tick / .4)!;
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(b.dx, b.dy);
      final p = Offset.lerp(b, d, (tick - .4) / .6)!;
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, stroke..strokeWidth = 7);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}
