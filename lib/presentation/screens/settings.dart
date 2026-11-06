import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/security_service.dart';
import '../controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final security = SecurityService();
  bool hasPin = false, biometric = false, securityLoaded = false, busy = false;
  @override
  void initState() {
    super.initState();
    _loadSecurity();
  }

  Future<void> _loadSecurity() async {
    try {
      final pin = await security.hasPin();
      final bio = await security.biometricEnabled;
      if (mounted) {
        setState(() {
          hasPin = pin;
          biometric = bio;
          securityLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => securityLoaded = false);
      }
    }
  }

  Future<void> _run(Future<void> Function() task) async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<bool> _verifyCurrent() async {
    if (!await security.hasPin()) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    final pin = await _requestPin(context, title: 'Текущий PIN');
    if (pin == null) {
      return false;
    }
    final valid = await security.verifyPin(pin);
    if (!valid && mounted) {
      showError(context, const FormatException('Неверный PIN.'));
    }
    return valid;
  }

  Future<void> _configurePin() async {
    if (!await _verifyCurrent() || !mounted) {
      return;
    }
    final pin = await _requestPin(
      context,
      title: 'Новый PIN',
      confirmEntry: true,
    );
    if (pin == null) {
      return;
    }
    await security.setPin(pin);
    await _loadSecurity();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'PIN установлен. Запомните его: восстановить PIN без удаления данных нельзя.',
          ),
        ),
      );
    }
  }

  Future<void> _removePin() async {
    if (!await _verifyCurrent() || !mounted) {
      return;
    }
    if (!await confirm(
      context,
      'Отключить защиту?',
      'Вход в приложение больше не будет требовать PIN или биометрию.',
    )) {
      return;
    }
    await security.removePin();
    await _loadSecurity();
  }

  Future<void> _toggleBiometric(bool value) async {
    if (!await _verifyCurrent()) {
      return;
    }
    if (value && !await security.biometricAvailable) {
      throw const FormatException(
        'Биометрия недоступна. Добавьте отпечаток пальца или лицо в настройках Android.',
      );
    }
    await security.setBiometricEnabled(value);
    if (value) {
      var verified = false;
      try {
        verified = await security.authenticateBiometric();
      } finally {
        if (!verified) {
          await security.setBiometricEnabled(false);
        }
      }
      if (!verified) {
        throw const FormatException('Биометрическая проверка не завершена.');
      }
    }
    await _loadSecurity();
  }

  Future<void> _export(String type) async {
    if (!await confirm(
      context,
      'Экспорт финансовых данных',
      'Файл содержит суммы, счета и историю операций без шифрования. Сохраните его в надёжном месте. PIN в файл не попадает.',
    )) {
      return;
    }
    if (!mounted) {
      return;
    }
    final c = FinanceScope.of(context);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final path = '${dir.path}/finora-$stamp.$type';
    if (type == 'db') {
      await c.repository.backupDatabase(path);
    } else {
      final content = type == 'csv'
          ? await c.repository.exportCsv()
          : await c.repository.exportJson();
      await File(path).writeAsString(content, flush: true);
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        subject: 'Резервная копия Finance',
        text: type == 'csv'
            ? 'Операции Finance'
            : 'Резервная копия Finance. Храните файл в безопасном месте.',
      ),
    );
  }

  Future<void> _import(String type) async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [type],
      withData: false,
    );
    if (pick == null || pick.files.isEmpty) {
      return;
    }
    final file = pick.files.single;
    if (file.size > 50 * 1024 * 1024) {
      throw const FormatException('Файл превышает 50 МБ.');
    }
    if (!mounted) {
      return;
    }
    if (!await confirm(
      context,
      'Заменить текущие данные?',
      'Импорт полностью заменит счета, операции, бюджеты, цели и настройки. Сначала экспортируйте текущую резервную копию. Повреждённый файл будет отклонён без изменения данных.',
    )) {
      return;
    }
    if (!mounted) {
      return;
    }
    final c = FinanceScope.of(context);
    if (type == 'json') {
      final path = file.path;
      if (path == null) {
        throw const FormatException('Не удалось получить доступ к файлу.');
      }
      final bytes = await File(path).readAsBytes();
      await c.importJson(utf8.decode(bytes));
    } else {
      final path = file.path;
      if (path == null) {
        throw const FormatException('Не удалось получить доступ к файлу.');
      }
      await c.restore(path);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Данные восстановлены. Настройки PIN остаются на этом устройстве.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final p = c.data.preferences;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: busy,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SectionTitle('Внешний вид'),
                SurfaceCard(
                  child: Column(
                    children: [
                      _setting<String>(
                        'Тема',
                        p.theme,
                        const {
                          'system': 'Как в системе',
                          'dark': 'Тёмная',
                          'light': 'Светлая',
                        },
                        (v) => _run(
                          () => c.preferences(
                            c.data.preferences.copyWith(theme: v),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _setting<String>(
                        'Визуальный стиль',
                        AppTheme.presetNames.containsKey(p.accent)
                            ? p.accent
                            : 'lime',
                        AppTheme.presetNames,
                        (v) => _run(
                          () => c.preferences(
                            c.data.preferences.copyWith(accent: v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Личные предпочтения'),
                SurfaceCard(
                  child: Column(
                    children: [
                      _setting<String>(
                        'Основная валюта',
                        p.baseCurrency,
                        {for (final v in currencies) v: v},
                        (v) => _run(
                          () => c.preferences(
                            c.data.preferences.copyWith(baseCurrency: v),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Баланс и аналитика показывают выбранную валюту. Средства в других валютах учитываются отдельно — без неявной конвертации.',
                        ),
                      ),
                      _setting<int>(
                        'Первый день недели',
                        p.weekStart,
                        const {1: 'Понедельник', 7: 'Воскресенье'},
                        (v) => _run(
                          () => c.preferences(
                            c.data.preferences.copyWith(weekStart: v),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _setting<int>(
                        'Начало финансового месяца',
                        p.monthStart,
                        {for (var day = 1; day <= 28; day++) day: '$day число'},
                        (v) => _run(
                          () => c.preferences(
                            c.data.preferences.copyWith(monthStart: v),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _setting<String>(
                        'Формат чисел',
                        p.numberFormat,
                        const {
                          'space_comma': '12 345,67',
                          'comma_dot': '12,345.67',
                        },
                        (v) => _run(
                          () => c.preferences(
                            c.data.preferences.copyWith(numberFormat: v),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _setting<String>(
                        'Формат даты',
                        p.dateFormat,
                        const {
                          'dd.MM.yyyy': '31.12.2026',
                          'yyyy-MM-dd': '2026-12-31',
                          'dd/MM/yyyy': '31/12/2026',
                        },
                        (v) => _run(
                          () => c.preferences(
                            c.data.preferences.copyWith(dateFormat: v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Уведомления'),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Финансовые напоминания'),
                        subtitle: const Text('Платежи, бюджеты, цели и отчёты'),
                        value: p.notifications,
                        onChanged: (value) => _run(() async {
                          if (value) {
                            final allowed = await c.notifications
                                .requestPermission();
                            if (!allowed) {
                              throw const FormatException(
                                'Разрешите уведомления для Finance в настройках Android.',
                              );
                            }
                          }
                          await c.preferences(
                            c.data.preferences.copyWith(notifications: value),
                          );
                          final result = await c.waitForNotificationSync();
                          if (!result.succeeded && context.mounted) {
                            showError(
                              context,
                              const FormatException(notificationSyncWarning),
                            );
                          }
                        }),
                      ),
                      if (c.notificationSyncPending) ...[
                        const SizedBox(height: 8),
                        const Text('Обновляем уведомления…'),
                      ],
                      if (c.notificationSyncResult?.succeeded == false) ...[
                        const SizedBox(height: 8),
                        const Text(
                          notificationSyncWarning,
                          key: ValueKey('notification-sync-warning'),
                        ),
                      ],
                      TextButton.icon(
                        key: const ValueKey('notification-sync-retry'),
                        onPressed: busy || c.notificationSyncPending
                            ? null
                            : () => _run(() async {
                                final result = await c.retryNotificationSync();
                                if (!context.mounted) return;
                                if (!result.succeeded) {
                                  showError(
                                    context,
                                    const FormatException(
                                      notificationSyncWarning,
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(
                                      const SnackBar(
                                        content: Text('Уведомления обновлены.'),
                                      ),
                                    );
                                }
                              }),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(
                          c.notificationSyncResult?.succeeded == false
                              ? 'Повторить обновление уведомлений'
                              : 'Обновить уведомления',
                        ),
                      ),
                      const Text(
                        'Android может задерживать уведомления для экономии батареи. Автоматические финансовые операции создаются при запуске приложения.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Защита'),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!securityLoaded)
                        OutlinedButton.icon(
                          onPressed: _loadSecurity,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Проверить доступность защиты'),
                        ),
                      if (securityLoaded) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.lock_outline),
                          title: Text(
                            hasPin ? 'Изменить PIN' : 'Установить PIN',
                          ),
                          subtitle: const Text('От 4 до 6 цифр'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _run(_configurePin),
                        ),
                        if (hasPin) ...[
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Биометрический вход'),
                            value: biometric,
                            onChanged: (v) => _run(() => _toggleBiometric(v)),
                          ),
                          const SizedBox(height: 14),
                          _setting<int>(
                            'Автоблокировка',
                            p.lockMinutes,
                            const {
                              0: 'Сразу',
                              1: 'Через минуту',
                              5: 'Через 5 минут',
                              15: 'Через 15 минут',
                            },
                            (v) => _run(
                              () => c.preferences(
                                c.data.preferences.copyWith(lockMinutes: v),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _run(_removePin),
                            child: const Text('Отключить PIN'),
                          ),
                        ],
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'PIN защищает вход в приложение. Экспортированные файлы и локальная база не шифруются отдельно. Защита устройства и безопасное хранение копий остаются важными.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Резервные копии'),
                SurfaceCard(
                  child: Column(
                    children: [
                      _backupAction(
                        'Экспорт JSON',
                        'Полная переносимая копия',
                        Icons.upload_file_outlined,
                        () => _run(() => _export('json')),
                      ),
                      _backupAction(
                        'Импорт JSON',
                        'Заменить текущие данные',
                        Icons.download_outlined,
                        () => _run(() => _import('json')),
                      ),
                      _backupAction(
                        'Экспорт CSV',
                        'Таблица операций для Excel',
                        Icons.table_chart_outlined,
                        () => _run(() => _export('csv')),
                      ),
                      _backupAction(
                        'Копия базы SQLite',
                        'Снимок локальной базы',
                        Icons.storage_outlined,
                        () => _run(() => _export('db')),
                      ),
                      _backupAction(
                        'Восстановить базу',
                        'Из файла SQLite',
                        Icons.restore_outlined,
                        () => _run(() => _import('db')),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Finance · 1.6.4',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'Finance',
                    applicationVersion: '1.6.4',
                  ),
                  icon: const Icon(Icons.article_outlined, size: 18),
                  label: const Text('Лицензии'),
                ),
                if (c.data.demo) ...[
                  const SectionTitle('Демонстрационный профиль'),
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Сейчас вы знакомитесь с примером семейных финансов. Очистка удалит только демонстрационные записи. Ваши собственные операции, цели и бюджеты сохранятся. Счета с вашими операциями останутся с нулевым начальным балансом.',
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => _run(() async {
                            if (!await confirm(
                              context,
                              'Очистить демонстрационные данные?',
                              'Будут удалены только примеры. Ваши записи сохранятся. Начальные балансы демонстрационных счетов с вашими операциями обнулятся. Рекомендуем сначала экспортировать копию.',
                            )) {
                              return;
                            }
                            await c.clearDemo();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Демонстрационные данные очищены. Ваши записи сохранены.',
                                  ),
                                ),
                              );
                            }
                          }),
                          child: const Text('Очистить демонстрационные данные'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (busy)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _backupAction(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

Widget _setting<T>(
  String title,
  T value,
  Map<T, String> values,
  void Function(T) change,
) => DropdownButtonFormField<T>(
  initialValue: value,
  isExpanded: true,
  decoration: InputDecoration(labelText: title),
  items: {...values, if (!values.containsKey(value)) value: value.toString()}
      .entries
      .map(
        (e) => DropdownMenuItem<T>(
          value: e.key,
          child: Text(e.value, overflow: TextOverflow.ellipsis),
        ),
      )
      .toList(),
  onChanged: (v) {
    if (v != null) {
      change(v);
    }
  },
);
Future<String?> _requestPin(
  BuildContext context, {
  required String title,
  bool confirmEntry = false,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PinDialog(title: title, confirmEntry: confirmEntry),
);

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title, required this.confirmEntry});
  final String title;
  final bool confirmEntry;
  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final first = TextEditingController();
  final second = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    first.dispose();
    second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: first,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(labelText: 'PIN'),
            validator: (v) => RegExp(r'^\d{4,6}$').hasMatch(v ?? '')
                ? null
                : 'Введите от 4 до 6 цифр',
          ),
          if (widget.confirmEntry) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: second,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(labelText: 'Повторите PIN'),
              validator: (v) => v == first.text ? null : 'PIN не совпадает',
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, first.text);
          }
        },
        child: const Text('Продолжить'),
      ),
    ],
  );
}
