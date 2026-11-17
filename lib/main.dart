import 'presentation/i18n.dart';
import 'dart:async';

import 'package:flutter/material.dart' hide InputDecoration, Text;
import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/finance_repository.dart';
import 'services/notification_service.dart';
import 'services/security_service.dart';
import 'services/receipt_share_service.dart';
import 'presentation/controller.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/widgets/finora_drawer.dart';
import 'presentation/widgets/finora_says.dart';
import 'features/finora_ai/ui/finora_ai_screen.dart';
import 'features/finora_ai/services/finora_ai.dart';
import 'presentation/screens/dashboard.dart';
import 'presentation/screens/transactions.dart';
import 'presentation/screens/analytics.dart';
import 'presentation/screens/management.dart';
import 'presentation/screens/entry_editor.dart';
import 'presentation/screens/onboarding.dart';
import 'presentation/widgets/common.dart';
import 'presentation/widgets/finance_background.dart';
import 'presentation/widgets/voice_orb.dart';
import 'presentation/widgets/finora_wordmark.dart';
import 'presentation/voice_commands.dart';
import 'presentation/haptics.dart';
import 'presentation/payment_prompt.dart';
import 'presentation/page_transitions.dart';
import 'presentation/release_celebration.dart';
import 'presentation/whats_new.dart';
import 'presentation/finora_outside.dart';
import 'presentation/widgets/finora_orb.dart';
import 'services/finora_system.dart';
import 'services/finora_ear.dart';
import 'presentation/finora_listening.dart';
import 'domain/voice_command_parser.dart';
import 'services/voice_input_service.dart';
import 'domain/models.dart';
import 'domain/achievements.dart';
import 'presentation/screens/achievements_screen.dart';
import 'presentation/l10n_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 1.37: month and day names in every app language.
  await initializeDateFormatting();
  // Finora AI: her memory and the local model load in the background.
  unawaited(FinoraAi.instance.ready());
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(
      'assets/ocr/THIRD_PARTY_NOTICES.txt',
    );
    yield LicenseEntryWithLineBreaks(const [
      'Tesseract4Android',
      'Tesseract',
      'Leptonica',
      'libjpeg',
      'libpng',
      'tessdata_fast',
    ], text);
  });
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  FinanceController? _controller;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    // 1.55: the «Finora» wordmark gets its moment, however fast the data
    // opens.
    final hello = Future<void>.delayed(const Duration(milliseconds: 1600));
    FinanceRepository? repository;
    try {
      repository = await FinanceRepository.open();
      final controller = FinanceController(
        repository,
        NotificationService(),
        await repository.load(),
      );
      await controller.processRecurring();
      await hello;
      if (mounted) {
        setState(() => _controller = controller);
      } else {
        await repository.close();
        controller.dispose();
      }
    } catch (e) {
      await repository?.close();
      if (mounted) {
        setState(() => _error = e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller != null) {
      return FinoraApp(controller: _controller!);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.dark, 'tropic'),
      home: Scaffold(
        // The same dark sky as the system splash; the wordmark is written.
        backgroundColor: const Color(0xFF040A12),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: _error == null
                ? const FinoraWordmark()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 44),
                      const SizedBox(height: 16),
                      const Text(
                        'Не удалось открыть данные',
                        style: TextStyle(fontSize: 22),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Данные не удалены. Проверьте свободное место и повторите запуск.\n$_error',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class FinoraApp extends StatelessWidget {
  const FinoraApp({
    super.key,
    required this.controller,
    this.requireDeviceSecurity = true,
  });
  final FinanceController controller;
  final bool requireDeviceSecurity;
  @override
  Widget build(BuildContext context) => FinanceScope(
    controller: controller,
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final p = controller.data.preferences;
        FinanceFormat.numberPattern = p.numberFormat;
        FinanceFormat.datePattern = p.dateFormat;
        Haptics.enabled = p.haptics;
        AppLanguage.code = p.language;
        // 1.36: Finora in the theme's color.
        FinoraOrbPainter.theme = p.finoraThemed
            ? AppTheme.app(Brightness.dark, p.accent).colorScheme.primary
            : FinoraOrbPainter.original;
        // 2.3: eyes and emotions, or a sphere of light.
        FinoraOrbPainter.plain = !p.finoraFace;
        return MaterialApp(
          title: 'Finora — личные финансы',
          debugShowCheckedModeBanner: false,
          // 1.28: the app language from Settings.
          locale: Locale(p.language),
          supportedLocales: [
            for (final code in AppLanguage.names.keys) Locale(code),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          // 1.27: every tap answers with a light tick.
          theme: withFinoraTransitions(
            withHaptics(AppTheme.app(Brightness.light, p.accent)),
          ),
          darkTheme: withFinoraTransitions(
            withHaptics(AppTheme.app(Brightness.dark, p.accent)),
          ),
          themeMode: switch (p.theme) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          builder: (context, child) => FinanceBackground(
            child: requireDeviceSecurity ? SecurityGate(child: child!) : child!,
          ),
          // 1.21: welcome screens on the very first launch.
          home: p.onboarded ? const HomeShell() : const OnboardingScreen(),
        );
      },
    ),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  final _receiptShares = ReceiptShareService();
  StreamSubscription<void>? _shareSubscription;
  bool _openingShare = false, _shareNeedsDrain = false;

  @override
  void initState() {
    super.initState();
    _shareSubscription = _receiptShares.imageAvailable.listen((_) {
      _shareNeedsDrain = true;
      unawaited(_takeSharedImage());
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_takeSharedImage()),
    );
    // 1.27: Finora asks about today's payments.
    WidgetsBinding.instance.addObserver(this);
    _askPayments();
    _actionSubscription = FinoraSystem.actions.listen(
      (a) => unawaited(_action(a)),
    );
    _wakeSubscription = FinoraEar.wakes.listen((h) => unawaited(_woken(h)));
    // The speech model is unpacked early, so the first tap is quick.
    unawaited(
      FinoraEar.available.then((yes) async {
        if (yes) await FinoraEar.prepare();
        unawaited(_listenForName());
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final action = await FinoraSystem.takeAction();
      if (action != null) await _action(action);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Widgets and the shade follow the data.
    final c = FinanceScope.of(context);
    if (!identical(c, _watched)) {
      _watched?.removeListener(_dataChanged);
      FinoraOutside.cancel();
      _watched = c..addListener(_dataChanged);
      FinoraOutside.schedule(c);
      // 1.44: «Достижение получено».
      _unlockSubscription?.cancel();
      _unlockSubscription = c.achievementUnlocks.listen((got) {
        if (mounted) AchievementPopup.show(context, got);
      });
    }
  }

  StreamSubscription<List<AchievementDefinition>>? _unlockSubscription;

  void _dataChanged() {
    final c = _watched;
    if (c != null) FinoraOutside.schedule(c);
  }

  Timer? _paymentsTimer;

  void _askPayments() {
    _paymentsTimer?.cancel();
    _paymentsTimer = Timer(const Duration(milliseconds: 900), () async {
      // Finora Release: the celebration once; otherwise, after an update,
      // «Что нового». Then the payments.
      final celebrated = mounted && await ReleaseCelebration.check(context);
      if (mounted && !celebrated) await WhatsNew.check(context);
      if (mounted) unawaited(PaymentPrompt.check(context));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _askPayments();
      unawaited(_listenForName());
    }
  }

  Future<void> _takeSharedImage() async {
    if (!mounted || _openingShare) return;
    _openingShare = true;
    _shareNeedsDrain = false;
    try {
      final path = await _receiptShares.takePendingImage();
      if (path != null && mounted) {
        await showEntryEditor(context, scanImagePath: path);
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      _openingShare = false;
      if (mounted && _shareNeedsDrain) unawaited(_takeSharedImage());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paymentsTimer?.cancel();
    unawaited(_actionSubscription?.cancel());
    unawaited(_unlockSubscription?.cancel());
    unawaited(_wakeSubscription?.cancel());
    _watched?.removeListener(_dataChanged);
    final subscription = _shareSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    unawaited(_receiptShares.dispose());
    super.dispose();
  }

  StreamSubscription<String>? _actionSubscription;
  FinanceController? _watched;

  /// 1.27: widgets, the Quick Settings tile and the shade open the app
  /// with an action.
  Future<void> _action(String action) async {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    switch (action) {
      case 'voice':
        await _voice();
      case 'expense':
        await showEntryEditor(context, kind: EntryKind.expense);
      case 'income':
        await showEntryEditor(context, kind: EntryKind.income);
      case 'scan':
        await showEntryEditor(context, startScan: true);
      case 'payments':
        await PaymentPrompt.check(context);
        if (mounted) {
          openFinancePage(context, const RecurringScreen());
        }
    }
  }

  /// The voice orb (1.23): a command («покажи расходы за июнь», «поменяй
  /// тему на зелёную») is carried out; anything else is an operation and
  /// opens the editor filled from the phrase.
  Future<void> _voice() async {
    List<String> heard;
    final prefs = FinanceScope.of(context).data.preferences;
    try {
      // 1.32: the accurate system recognizer; Finora's own silent ear only
      // when chosen in Settings («Тихое распознавание»).
      if (prefs.quietVoice && await FinoraEar.available) {
        if (!await FinoraEar.micAllowed() && !await FinoraEar.requestMic()) {
          if (mounted) {
            showError(
              context,
              const FormatException(
                'Разрешите микрофон для Finora, чтобы Финора вас слышала.',
              ),
            );
          }
          return;
        }
        if (!mounted) return;
        heard = await listenWithFinora(context);
      } else {
        heard = await const VoiceInputService().listen(
          prompt: VoiceCommands.prompt,
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
      unawaited(_listenForName());
      return;
    }
    if (heard.isEmpty || !mounted) {
      unawaited(_listenForName());
      return;
    }
    await _heard(heard);
    unawaited(_listenForName());
  }

  StreamSubscription<List<String>>? _wakeSubscription;

  /// 1.31: «Финора» while the app is on screen, when turned on in Settings.
  /// Never in the background (the ear stops when the app is paused).
  Future<void> _listenForName() async {
    if (!mounted) return;
    final c = FinanceScope.of(context);
    if (!c.data.preferences.wakeWord ||
        !await FinoraEar.available ||
        !await FinoraEar.micAllowed() ||
        !mounted) {
      return;
    }
    await FinoraEar.wakeStart(const []);
  }

  Future<void> _woken(List<String> heard) async {
    if (!mounted) return;
    // 1.32: her name only; the request itself goes to the accurate
    // recognizer.
    Finora.react(FinoraMood.greeting, text: 'Слушаю!');
    await _voice();
  }

  /// A phrase heard by the speech dialog.
  Future<void> _heard(List<String> heard) async {
    final c = FinanceScope.of(context);
    final command = VoiceCommandParser.parse(
      heard,
      categories: c.data.categories,
      accounts: c.data.accounts,
      weekStart: c.data.preferences.weekStart,
    );
    if (command == null) {
      await showEntryEditor(context, voiceHeard: heard);
    } else {
      await VoiceCommands.run(
        context,
        command,
        onTab: (tab) {
          if (mounted) setState(() => _tab = tab);
        },
      );
    }
  }

  final _scaffold = GlobalKey<ScaffoldState>();
  Offset? _downAt;

  /// The menu button that opens the side panel.
  Widget _menuButton({Color? color}) => IconButton(
    key: const ValueKey('nav-menu'),
    tooltip: tr('Меню'),
    onPressed: () {
      Haptics.light();
      _scaffold.currentState?.openDrawer();
    },
    icon: CustomPaint(
      size: const Size(24, 24),
      painter: _MenuGlyph(color ?? Theme.of(context).colorScheme.onSurface),
    ),
  );

  void _select(int tab) {
    if (tab != _tab) setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final ai = _tab == 5;
    final page = switch (_tab) {
      0 => Dashboard(
        onTransactions: () => _select(1),
        onAnalytics: () => _select(3),
      ),
      1 => const TransactionsScreen(),
      3 => const AnalyticsScreen(),
      5 => FinoraAiScreen(
        embedded: true,
        leading: _menuButton(color: Colors.white),
      ),
      _ => const MoreScreen(),
    };
    // Any tap (not a scroll) wakes the voice orb's animation.
    return Listener(
      onPointerDown: (e) => _downAt = e.position,
      onPointerUp: (e) {
        final from = _downAt;
        if (from != null && (e.position - from).distance < 12) {
          VoiceOrb.activity.value++;
        }
        _downAt = null;
      },
      child: Scaffold(
        key: _scaffold,
        // Release: navigation is a side panel (menu button or a swipe from
        // the left edge), like a chat app.
        drawer: FinoraDrawer(current: _tab, onSelect: _select, onVoice: _voice),
        drawerEdgeDragWidth: 32,
        // The AI window has a text field; the main screens have none (a
        // keyboard closing late after the welcome screens must not squeeze
        // them, 1.22.1).
        resizeToAvoidBottomInset: ai,
        body: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, .015),
                      end: Offset.zero,
                    ).animate(animation),
                    child: ScaleTransition(
                      scale: Tween(begin: .985, end: 1.0).animate(animation),
                      child: child,
                    ),
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_tab),
                  child: ai
                      ? page
                      : _tab == 0
                      // Home: the menu sits in the header row, beside the
                      // balance.
                      ? SafeArea(
                          bottom: false,
                          child: Stack(
                            children: [
                              Positioned.fill(child: page),
                              Positioned(top: 2, left: 8, child: _menuButton()),
                            ],
                          ),
                        )
                      : SafeArea(
                          bottom: false,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                                child: Row(children: [_menuButton()]),
                              ),
                              Expanded(child: page),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            // Finora's short lines, while the orb has no place on screen.
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: EdgeInsets.only(bottom: 18),
                child: Center(heightFactor: 1, child: FinoraSays()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two lines, the lower one shorter — the menu symbol.
class _MenuGlyph extends CustomPainter {
  const _MenuGlyph(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    canvas
      ..drawLine(
        Offset(w * .14, size.height * .38),
        Offset(w * .86, size.height * .38),
        p,
      )
      ..drawLine(
        Offset(w * .14, size.height * .62),
        Offset(w * .6, size.height * .62),
        p,
      );
  }

  @override
  bool shouldRepaint(_MenuGlyph old) => old.color != color;
}

class SecurityGate extends StatefulWidget {
  const SecurityGate({super.key, required this.child});
  final Widget child;
  @override
  State<SecurityGate> createState() => _SecurityGateState();
}

class _SecurityGateState extends State<SecurityGate>
    with WidgetsBindingObserver {
  final _security = SecurityService();
  final _pin = TextEditingController();
  bool _locked = true, _ready = false, _busy = false, _biometric = false;
  DateTime? _paused;
  Timer? _idleTimer;
  bool _hasPin = false, _refreshing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SecurityService.revision.addListener(_refreshSecurity);
    _check();
  }

  Future<void> _check({bool catchUp = false}) async {
    try {
      final pin = await _security.hasPin();
      final bio = await _security.biometricEnabled;
      if (mounted) {
        setState(() {
          _ready = true;
          _hasPin = pin;
          _locked = pin;
          _biometric = bio;
          _error = null;
        });
        if (catchUp && !pin) {
          unawaited(
            FinanceScope.of(context).processRecurring().catchError((Object e) {
              if (mounted) {
                showError(context, e);
              }
            }),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ready = true;
          _locked = true;
          _error = 'Защищённое хранилище недоступно. Повторите запуск.';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SecurityService.revision.removeListener(_refreshSecurity);
    _idleTimer?.cancel();
    _pin.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SecurityGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshSecurity();
  }

  Future<void> _refreshSecurity() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      final configured = await _security.hasPin();
      final bio = await _security.biometricEnabled;
      if (mounted) {
        setState(() {
          _hasPin = configured;
          _biometric = bio;
        });
        _activity();
      }
    } catch (_) {
      /* A storage failure never unlocks the gate. */
    } finally {
      _refreshing = false;
    }
  }

  void _activity() {
    _idleTimer?.cancel();
    if (!_hasPin || _locked || !mounted) {
      return;
    }
    final minutes = FinanceScope.of(context).data.preferences.lockMinutes;
    if (minutes == 0) {
      return;
    } // Zero means lock immediately on background/resume.
    _idleTimer = Timer(Duration(minutes: minutes), () {
      if (!mounted || _busy) {
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _locked = true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _paused ??= DateTime.now();
      _idleTimer?.cancel();
    }
    if (state == AppLifecycleState.resumed) {
      final elapsed = _paused == null
          ? Duration.zero
          : DateTime.now().difference(_paused!);
      _paused = null;
      final minutes = FinanceScope.of(context).data.preferences.lockMinutes;
      if (elapsed >= Duration(minutes: minutes) && !_busy) {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _locked = true);
        _check(catchUp: true);
      }
      if (!_locked) {
        _activity();
        unawaited(
          FinanceScope.of(context).processRecurring().catchError((Object e) {
            if (mounted) {
              showError(context, e);
            }
          }),
        );
      }
    }
  }

  Future<void> _unlock({bool biometric = false}) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final valid = biometric
          ? await _security.authenticateBiometric()
          : await _security.verifyPin(_pin.text);
      if (mounted) {
        setState(() {
          _locked = !valid;
          _pin.clear();
          _error = valid ? null : 'Не удалось подтвердить вход. Проверьте PIN.';
        });
        if (valid) {
          _activity();
          unawaited(
            FinanceScope.of(context).processRecurring().catchError((Object e) {
              if (mounted) {
                showError(context, e);
              }
            }),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Не удалось проверить защиту устройства.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final lockScreen = PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Ваши финансы\nпод защитой',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text('Введите PIN для входа в Finora'),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'PIN-код',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _unlock(),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : () => _unlock(),
                        child: Text(_busy ? 'Проверяем…' : 'Войти'),
                      ),
                    ),
                    if (_biometric)
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _unlock(biometric: true),
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Войти по биометрии'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _activity(),
      onPointerMove: (_) => _activity(),
      child: Stack(
        children: [
          ExcludeFocus(
            excluding: _locked,
            child: Offstage(
              offstage: _locked,
              child: TickerMode(enabled: !_locked, child: widget.child),
            ),
          ),
          if (_locked) Positioned.fill(child: lockScreen),
        ],
      ),
    );
  }
}

/// The loading screen (1.29): Finora stands exactly where she was on the
/// system splash and comes alive — hops for joy, beams, sparkles, waves
/// rings — while the data opens.
class HelloFinora extends StatelessWidget {
  const HelloFinora({super.key});
  static const _size = 146.0;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // 1.34: the whole screen, not the orb's own box — the words sit below
    // her and never cover her face.
    builder: (context, box) {
      final h = box.maxHeight.isFinite ? box.maxHeight : 640.0;
      return SizedBox(
        key: const ValueKey('loading-finora'),
        width: box.maxWidth.isFinite ? box.maxWidth : 360,
        height: h,
        child: Stack(
          children: [
            // The splash draws her 146 dp wide in the middle of the screen.
            const Center(
              child: FinoraCharacter(
                size: _size,
                moods: [
                  FinoraMood.delight,
                  FinoraMood.happy,
                  FinoraMood.greeting,
                  FinoraMood.delight,
                ],
                step: Duration(milliseconds: 650),
                loop: true,
                rings: false,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: h / 2 + _size / 2 + 44,
              child: const Column(
                key: ValueKey('loading-finora-text'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Привет! Я Финора',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Открываю ваши финансы…',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0x99DFFFF8)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
