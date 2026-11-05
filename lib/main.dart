import 'dart:async';

import 'package:flutter/material.dart';
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
import 'presentation/screens/dashboard.dart';
import 'presentation/screens/transactions.dart';
import 'presentation/screens/analytics.dart';
import 'presentation/screens/management.dart';
import 'presentation/screens/entry_editor.dart';
import 'presentation/widgets/common.dart';
import 'presentation/widgets/finance_header.dart';
import 'domain/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
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
    FinanceRepository? repository;
    try {
      repository = await FinanceRepository.open();
      final controller = FinanceController(
        repository,
        NotificationService(),
        await repository.load(),
      );
      await controller.processRecurring();
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
      theme: AppTheme.build(Brightness.dark, 'coffee'),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: _error == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 64, height: 64, child: FinanceBrand()),
                      SizedBox(height: 20),
                      Text(
                        'FINANCE',
                        style: TextStyle(fontSize: 22, letterSpacing: 4),
                      ),
                      SizedBox(height: 24),
                      CircularProgressIndicator(),
                    ],
                  )
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
        return MaterialApp(
          title: 'Finance — личные финансы',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.build(Brightness.light, p.accent),
          darkTheme: AppTheme.build(Brightness.dark, p.accent),
          themeMode: switch (p.theme) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          builder: requireDeviceSecurity
              ? (context, child) => SecurityGate(child: child!)
              : null,
          home: const HomeShell(),
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

class _HomeShellState extends State<HomeShell> {
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
    final subscription = _shareSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    unawaited(_receiptShares.dispose());
    super.dispose();
  }

  Future<void> _add() async {
    final kind = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Новая операция',
                  style: Theme.of(ctx).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                for (final item in [
                  (
                    EntryKind.expense,
                    'Расход',
                    'Покупка или платёж',
                    Icons.north_east_rounded,
                  ),
                  (
                    EntryKind.income,
                    'Доход',
                    'Поступление на счёт',
                    Icons.south_west_rounded,
                  ),
                  (
                    EntryKind.transfer,
                    'Перевод',
                    'Между своими счетами',
                    Icons.swap_horiz_rounded,
                  ),
                ])
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    leading: CategoryBadge(
                      icon: item.$4,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                    title: Text(item.$2),
                    subtitle: Text(item.$3),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(ctx, item.$1),
                  ),
                ListTile(
                  leading: const Icon(Icons.document_scanner_outlined),
                  title: const Text('Чек или скриншот'),
                  subtitle: const Text('Распознать сумму и категорию'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(ctx, 'scan'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (kind == 'scan' && mounted) {
      await showEntryEditor(context, startScan: true);
    } else if (kind is EntryKind && mounted) {
      await showEntryEditor(context, kind: kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey(_tab),
            child: switch (_tab) {
              0 => Dashboard(
                onTransactions: () => setState(() => _tab = 1),
                onAnalytics: () => setState(() => _tab = 3),
              ),
              1 => const TransactionsScreen(),
              3 => const AnalyticsScreen(),
              _ => const MoreScreen(),
            },
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .14),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(
            children: [
              _nav(0, Icons.space_dashboard_outlined, 'Главная'),
              _nav(1, Icons.receipt_long_outlined, 'Операции'),
              Expanded(
                child: Center(
                  heightFactor: 1,
                  child: Semantics(
                    label: 'Добавить операцию',
                    button: true,
                    child: InkWell(
                      onTap: _add,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: .18),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          size: 30,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _nav(3, Icons.bar_chart_rounded, 'Аналитика'),
              _nav(4, Icons.grid_view_rounded, 'Ещё'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nav(int index, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    final active = _tab == index;
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        label: label,
        child: InkWell(
          onTap: () => setState(() => _tab = index),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: active ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
                    size: 23,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
                    const Text('Введите PIN для входа в Finance'),
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
