import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models.dart';
import '../controller.dart';
import '../widgets/motion.dart';
import 'account_import_screen.dart';

/// Welcome screens on the first launch (Finance 1.21), in the spirit of
/// setting up a new iPhone: «Привет» in many languages, the person's name,
/// light or dark, where the data comes from, done.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  final _name = TextEditingController();
  int _page = 0;
  bool _busy = false;

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  void _go(int page) {
    FocusScope.of(context).unfocus();
    setState(() => _page = page);
    if (Motion.reduced(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 420),
        curve: Motion.curve,
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
      if (choice != 'example') {
        // Start clean: the demo ledger goes, the name and look stay.
        if (c.data.demo) await c.resetAll();
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

  Future<void> _finish() async {
    final c = FinanceScope.of(context);
    HapticFeedback.mediumImpact();
    await c.mutate(
      (d) => d.copyWith(preferences: d.preferences.copyWith(onboarded: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final name = c.data.preferences.userName;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Hello(onStart: () => _go(1)),
                _Step(
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
                  child: TextField(
                    key: const ValueKey('onboarding-name'),
                    controller: _name,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.words,
                    style: Theme.of(context).textTheme.headlineMedium,
                    decoration: const InputDecoration(hintText: 'Имя'),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) async {
                      if (_name.text.trim().isEmpty) return;
                      await _saveName();
                      if (mounted) _go(2);
                    },
                  ),
                ),
                _Step(
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
                  title: 'Перенести данные?',
                  subtitle:
                      'Счета из другой домашней бухгалтерии можно перенести '
                      'по скриншоту — с названиями и остатками.',
                  child: Column(
                    children: [
                      _Choice(
                        key: const ValueKey('onboarding-import'),
                        icon: Icons.add_photo_alternate_outlined,
                        title: 'Перенести счета со скриншота',
                        subtitle: 'Дзен-мани, CoinKeeper, Monefy, банк…',
                        onTap: _busy ? null : () => _source('import'),
                      ),
                      _Choice(
                        key: const ValueKey('onboarding-clean'),
                        icon: Icons.auto_awesome_outlined,
                        title: 'Начать с чистого листа',
                        subtitle: 'Добавите счета сами',
                        onTap: _busy ? null : () => _source('clean'),
                      ),
                      _Choice(
                        key: const ValueKey('onboarding-example'),
                        icon: Icons.visibility_outlined,
                        title: 'Посмотреть на примере',
                        subtitle: 'Демо-данные, потом их можно очистить',
                        onTap: _busy ? null : () => _source('example'),
                      ),
                    ],
                  ),
                ),
                _Done(name: name, visible: _page == 4, onFinish: _finish),
              ],
            ),
            if (_page > 0 && _page < 4)
              Positioned(
                left: 4,
                top: 4,
                child: TextButton.icon(
                  key: const ValueKey('onboarding-back'),
                  onPressed: () => _go(_page - 1),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                  label: const Text('Назад'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// «Привет» that turns into hellos in other languages, softly.
class _Hello extends StatefulWidget {
  const _Hello({required this.onStart});
  final VoidCallback onStart;
  @override
  State<_Hello> createState() => _HelloState();
}

class _HelloState extends State<_Hello> {
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
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    if (Motion.ambient(context)) {
      _timer = Timer.periodic(const Duration(milliseconds: 1700), (_) {
        if (!mounted) return;
        setState(() => _i = (_i + 1) % _words.length);
        // One round, then it rests on «Привет».
        if (_i == _words.length - 1) _timer?.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        children: [
          const Spacer(flex: 3),
          SizedBox(
            height: 110,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 650),
              switchInCurve: Motion.curve,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(
                  scale: Tween(begin: .94, end: 1.0).animate(a),
                  child: child,
                ),
              ),
              child: FittedBox(
                key: ValueKey(_i),
                fit: BoxFit.scaleDown,
                child: Text(
                  _words[_i],
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.5,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Finance — ваши деньги под контролем',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          const Spacer(flex: 4),
          _PrimaryButton(
            key: const ValueKey('onboarding-start'),
            label: 'Начать',
            onPressed: widget.onStart,
          ),
        ],
      ),
    );
  }
}

/// One setup step: a large title, a line of explanation, the content, and
/// the main button at the bottom.
class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    required this.subtitle,
    required this.child,
    this.primary,
    this.onPrimary,
    this.secondary,
    this.onSecondary,
  });
  final String title, subtitle;
  final Widget child;
  final String? primary, secondary;
  final VoidCallback? onPrimary, onSecondary;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 64, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 36),
          Expanded(child: SingleChildScrollView(child: child)),
          if (primary != null)
            _PrimaryButton(
              key: ValueKey('onboarding-$primary'),
              label: primary!,
              onPressed: onPrimary,
            ),
          if (secondary != null)
            TextButton(onPressed: onSecondary, child: Text(secondary!)),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({super.key, required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 54,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    ),
  );
}

/// Light / dark / system, each with a small phone preview.
class _Appearance extends StatelessWidget {
  const _Appearance({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget option(String id, String label, Color back, Color ink) => Expanded(
      child: GestureDetector(
        key: ValueKey('onboarding-theme-$id'),
        onTap: () => onChanged(id),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 150,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: back,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: value == id ? scheme.primary : scheme.outlineVariant,
                  width: value == id ? 2.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final w in [.7, .45, .9, .55])
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      height: 9,
                      width: 70 * w,
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Icon(
              value == id ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: value == id ? scheme.primary : scheme.outlineVariant,
            ),
          ],
        ),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            option('light', 'Светлое', const Color(0xFFF6F6F2), Colors.black),
            option('dark', 'Тёмное', const Color(0xFF1C1E21), Colors.white),
          ],
        ),
        const SizedBox(height: 18),
        TextButton(
          key: const ValueKey('onboarding-theme-system'),
          onPressed: () => onChanged('system'),
          child: Text(value == 'system' ? '✓ Как в системе' : 'Как в системе'),
        ),
      ],
    );
  }
}

/// A row of the data step, iOS settings style.
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            child: Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Всё готово»: a check that grows in, then the way into the app.
class _Done extends StatelessWidget {
  const _Done({
    required this.name,
    required this.visible,
    required this.onFinish,
  });
  final String name;
  final bool visible;
  final VoidCallback onFinish;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Column(
        children: [
          const Spacer(flex: 3),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: visible ? 0 : 1, end: 1),
            duration: Motion.reduced(context)
                ? Duration.zero
                : const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, t, child) =>
                Transform.scale(scale: .4 + .6 * t, child: child),
            child: Icon(
              Icons.check_circle_rounded,
              size: 96,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            name.isEmpty ? 'Всё готово!' : 'Всё готово, $name!',
            key: const ValueKey('onboarding-done'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Нажмите на круг внизу экрана и скажите, например: '
            '«Пятёрочка 450 рублей».',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          const Spacer(flex: 4),
          _PrimaryButton(
            key: const ValueKey('onboarding-finish'),
            label: 'Начать пользоваться',
            onPressed: onFinish,
          ),
        ],
      ),
    );
  }
}
