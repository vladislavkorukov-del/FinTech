import '../i18n.dart';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models.dart';
import '../../services/security_service.dart';
import '../../services/user_files.dart';
import '../controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'account_import_screen.dart';
import 'tutorial.dart';
import '../finora_outside.dart';
import '../widgets/grouped_list.dart';
import '../widgets/finora_orb.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.section});

  /// One page of settings (1.26): general, appearance, notifications,
  /// security, backups or about; null for the list of them.
  final String? section;
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
        subject: 'Резервная копия Finora',
        text: type == 'csv'
            ? 'Операции Finora'
            : 'Резервная копия Finora. Храните файл в безопасном месте.',
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

  static const version = '1.30.0';

  /// One settings page: a section of the root list.
  Widget _page(String title, List<Widget> children) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Stack(
      children: [
        AbsorbPointer(
          absorbing: busy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: children,
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

  void _open(String section) => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => SettingsScreen(section: section)),
  );

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final p = c.data.preferences;
    switch (widget.section) {
      case 'general':
        return _page(tr('Основные'), [
          SurfaceCard(
            child: Column(
              children: [
                // 1.21: the name from the welcome screens.
                TextFormField(
                  key: const ValueKey('settings-name'),
                  initialValue: p.userName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr('Ваше имя')),
                  onFieldSubmitted: (value) => _run(() async {
                    final name = value.trim();
                    await c.mutate(
                      (d) => d.copyWith(
                        preferences: d.preferences.copyWith(userName: name),
                        members: [
                          for (final m in d.members)
                            m.id == 'me' && name.isNotEmpty
                                ? Member(id: 'me', name: name)
                                : m,
                        ],
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
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
                  const {'space_comma': '12 345,67', 'comma_dot': '12,345.67'},
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
        ]);
      case 'appearance':
        return _page(tr('Внешний вид'), [
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
                    () => c.preferences(c.data.preferences.copyWith(theme: v)),
                  ),
                ),
                const SizedBox(height: 14),
                _StyleGallery(
                  selected: p.accent,
                  brightness: Theme.of(context).brightness,
                  onSelected: (v) => _run(
                    () => c.preferences(c.data.preferences.copyWith(accent: v)),
                  ),
                ),
                const SizedBox(height: 12),
                _setting<String>(
                  'Визуальный стиль',
                  AppTheme.presetNames.containsKey(p.accent)
                      ? p.accent
                      : 'lime',
                  AppTheme.presetNames,
                  (v) => _run(
                    () => c.preferences(c.data.preferences.copyWith(accent: v)),
                  ),
                ),
              ],
            ),
          ),
        ]);
      case 'notifications':
        return _page(tr('Уведомления'), [
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
                      final allowed = await c.notifications.requestPermission();
                      if (!allowed) {
                        throw const FormatException(
                          'Разрешите уведомления для Finora в настройках Android.',
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
                              const FormatException(notificationSyncWarning),
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
        ]);
      case 'security':
        return _page(tr('Защита'), [
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
                    title: Text(hasPin ? 'Изменить PIN' : 'Установить PIN'),
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
        ]);
      case 'backups':
        return _page(tr('Резервные копии'), [
          GroupedSection(
            title: 'Сохранить',
            footer:
                'Файлы не шифруются: храните их в надёжном месте. PIN в копию '
                'не попадает.',
            children: [
              GroupedRow(
                key: const ValueKey('backup-json'),
                icon: Icons.upload_file_rounded,
                color: TileColors.blue,
                title: 'Полная копия',
                subtitle: 'JSON — для переноса на другой телефон',
                onTap: () => _run(() => _export('json')),
              ),
              GroupedRow(
                icon: Icons.table_chart_rounded,
                color: TileColors.green,
                title: 'Таблица операций',
                subtitle: 'CSV для Excel и Google Таблиц',
                onTap: () => _run(() => _export('csv')),
              ),
              GroupedRow(
                icon: Icons.storage_rounded,
                color: TileColors.indigo,
                title: 'Снимок базы',
                subtitle: 'Файл SQLite целиком',
                onTap: () => _run(() => _export('db')),
              ),
            ],
          ),
          GroupedSection(
            title: 'Восстановить',
            footer: 'Восстановление заменит все текущие данные.',
            children: [
              GroupedRow(
                icon: Icons.download_rounded,
                color: TileColors.orange,
                title: 'Из полной копии',
                subtitle: 'Файл JSON',
                onTap: () => _run(() => _import('json')),
              ),
              GroupedRow(
                icon: Icons.restore_rounded,
                color: TileColors.gray,
                title: 'Из снимка базы',
                subtitle: 'Файл SQLite',
                onTap: () => _run(() => _import('db')),
              ),
            ],
          ),
        ]);
      case 'about':
        return _page(tr('О приложении'), [
          const SizedBox(height: 12),
          const Center(child: FinoraMark(size: 72)),
          const SizedBox(height: 12),
          Text(
            'Finora',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Версия $version · ваш финансовый ассистент',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          GroupedSection(
            footer:
                'Данные хранятся только на этом телефоне. Приложение не '
                'обращается к интернету.',
            children: [
              GroupedRow(
                icon: Icons.article_rounded,
                color: TileColors.gray,
                title: 'Лицензии',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Finora',
                  applicationVersion: version,
                ),
              ),
            ],
          ),
        ]);
    }
    final name = p.userName.trim();
    final themeName = switch (p.theme) {
      'light' => 'Светлая',
      'system' => 'Как в системе',
      _ => 'Тёмная',
    };
    final style = (AppTheme.presetNames[p.accent] ?? p.accent)
        .split(' · ')
        .first;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Настройки'))),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                // 1.26: who uses the app, at the top like on the iPhone.
                SurfaceCard(
                  key: const ValueKey('settings-profile'),
                  padding: const EdgeInsets.all(16),
                  onTap: () => _open('general'),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        child: Text(
                          name.isEmpty ? 'F' : name[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? 'Ваше имя' : name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr('Имя, валюта, форматы'),
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                GroupedSection(
                  title: tr('Основное'),
                  children: [
                    GroupedRow(
                      key: const ValueKey('settings-appearance'),
                      icon: Icons.palette_rounded,
                      color: TileColors.purple,
                      title: tr('Внешний вид'),
                      value: '$themeName · $style',
                      onTap: () => _open('appearance'),
                    ),
                    // 1.28: the app language.
                    GroupedRow(
                      key: const ValueKey('settings-language'),
                      icon: Icons.translate_rounded,
                      color: TileColors.teal,
                      title: tr('Язык'),
                      value: AppLanguage.names[p.language] ?? p.language,
                      onTap: () => _run(_chooseLanguage),
                    ),
                    GroupedRow(
                      key: const ValueKey('settings-general'),
                      icon: Icons.tune_rounded,
                      color: TileColors.blue,
                      title: tr('Валюта и форматы'),
                      value: p.baseCurrency,
                      onTap: () => _open('general'),
                    ),
                    GroupedRow(
                      key: const ValueKey('settings-notifications'),
                      icon: Icons.notifications_rounded,
                      color: TileColors.red,
                      title: tr('Уведомления'),
                      value: p.notifications ? 'Вкл.' : 'Выкл.',
                      onTap: () => _open('notifications'),
                    ),
                    GroupedRow(
                      key: const ValueKey('settings-security'),
                      icon: Icons.lock_rounded,
                      color: TileColors.green,
                      title: tr('Защита'),
                      value: !securityLoaded
                          ? null
                          : hasPin
                          ? (biometric ? 'PIN и отпечаток' : 'PIN')
                          : 'Выкл.',
                      onTap: () => _open('security'),
                    ),
                  ],
                ),
                GroupedSection(
                  title: tr('Данные'),
                  children: [
                    GroupedRow(
                      key: const ValueKey('settings-backups'),
                      icon: Icons.cloud_upload_rounded,
                      color: TileColors.indigo,
                      title: tr('Резервные копии'),
                      subtitle: tr('Сохранить и восстановить'),
                      onTap: () => _open('backups'),
                    ),
                    // 1.22.1: accounts from another finance app.
                    GroupedRow(
                      key: const ValueKey('settings-import'),
                      icon: Icons.move_down_rounded,
                      color: TileColors.teal,
                      title: tr('Перенести счета со скриншота'),
                      subtitle: tr('Из другого приложения или банка'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const AccountImportScreen(),
                        ),
                      ),
                    ),
                    if (c.data.demo)
                      GroupedRow(
                        key: const ValueKey('settings-clear-demo'),
                        icon: Icons.cleaning_services_rounded,
                        color: TileColors.orange,
                        title: 'Убрать пример',
                        subtitle: 'Ваши записи сохранятся',
                        onTap: () => _run(_clearDemo),
                      ),
                  ],
                ),
                // 1.27: Finora herself.
                GroupedSection(
                  title: tr('Финора'),
                  footer:
                      'Виджеты: удерживайте рабочий стол → «Виджеты» → Finora. '
                      'Плитка: опустите шторку → карандаш → «Финора».',
                  children: [
                    GroupedRow(
                      key: const ValueKey('settings-shade'),
                      icon: Icons.notifications_active_rounded,
                      color: TileColors.indigo,
                      title: tr('Финора в шторке'),
                      subtitle: 'Кнопки «Сказать», «Расход», «Скриншот»',
                      trailing: Switch.adaptive(
                        value: p.shadeControls,
                        onChanged: (v) => _run(() => _setShade(v)),
                      ),
                      onTap: () => _run(() => _setShade(!p.shadeControls)),
                    ),
                    GroupedRow(
                      key: const ValueKey('settings-tips'),
                      icon: Icons.lightbulb_rounded,
                      color: TileColors.orange,
                      title: tr('Советы по финансам'),
                      subtitle: tr('Карточка Финоры на главной'),
                      trailing: Switch.adaptive(
                        value: p.tips,
                        onChanged: (v) => _run(
                          () => c.preferences(
                            c.data.preferences.copyWith(tips: v),
                          ),
                        ),
                      ),
                      onTap: () => _run(
                        () => c.preferences(
                          c.data.preferences.copyWith(tips: !p.tips),
                        ),
                      ),
                    ),
                    GroupedRow(
                      key: const ValueKey('settings-haptics'),
                      icon: Icons.vibration_rounded,
                      color: TileColors.pink,
                      title: tr('Тактильный отклик'),
                      subtitle: tr('Лёгкая отдача на нажатия и реакции'),
                      trailing: Switch.adaptive(
                        value: p.haptics,
                        onChanged: (v) => _run(
                          () => c.preferences(
                            c.data.preferences.copyWith(haptics: v),
                          ),
                        ),
                      ),
                      onTap: () => _run(
                        () => c.preferences(
                          c.data.preferences.copyWith(haptics: !p.haptics),
                        ),
                      ),
                    ),
                  ],
                ),
                GroupedSection(
                  title: 'Finora',
                  children: [
                    // 1.25: the app tour from the welcome screens, again.
                    GroupedRow(
                      key: const ValueKey('settings-tutorial'),
                      icon: Icons.school_rounded,
                      color: TileColors.orange,
                      title: tr('Что умеет Finora'),
                      subtitle: tr('Короткое обучение'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<bool>(
                          fullscreenDialog: true,
                          builder: (_) => const TutorialScreen(),
                        ),
                      ),
                    ),
                    GroupedRow(
                      key: const ValueKey('settings-about'),
                      icon: Icons.info_rounded,
                      color: TileColors.gray,
                      title: tr('О приложении'),
                      value: version,
                      onTap: () => _open('about'),
                    ),
                  ],
                ),
                // 1.26: quiet, at the end; a swipe confirms it.
                GroupedSection(
                  footer:
                      'Удалит операции, счета, мечты, бюджеты и платежи. '
                      'Тема и имя останутся.',
                  children: [
                    GroupedRow(
                      key: const ValueKey('reset-all'),
                      icon: Icons.restart_alt_rounded,
                      color: TileColors.red,
                      title: tr('Сбросить все данные'),
                      destructive: true,
                      onTap: () => _run(_resetAll),
                    ),
                  ],
                ),
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

  /// «Финора в шторке»: an ongoing notification with her buttons.
  Future<void> _setShade(bool on) async {
    final c = FinanceScope.of(context);
    if (on && !await c.notifications.requestPermission()) {
      throw const FormatException(
        'Разрешите уведомления для Finora в настройках Android.',
      );
    }
    await c.preferences(c.data.preferences.copyWith(shadeControls: on));
    await FinoraOutside.push(c);
  }

  Future<void> _chooseLanguage() async {
    final c = FinanceScope.of(context);
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in AppLanguage.names.entries)
              ListTile(
                key: ValueKey('language-${e.key}'),
                leading: Icon(
                  e.key == c.data.preferences.language
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                ),
                title: Text(e.value),
                onTap: () => Navigator.pop(ctx, e.key),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                'English covers the main screens; voice commands and tips '
                'stay in Russian for now.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (code == null) return;
    await c.preferences(c.data.preferences.copyWith(language: code));
  }

  Future<void> _clearDemo() async {
    final c = FinanceScope.of(context);
    if (!await confirm(
      context,
      'Убрать пример?',
      'Будут удалены только примеры. Ваши записи сохранятся. Начальные '
          'балансы демонстрационных счетов с вашими операциями обнулятся.',
    )) {
      return;
    }
    await c.clearDemo();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пример убран. Ваши записи сохранены.')),
      );
    }
  }

  /// Asks the person to type «СБРОС», then erases all data and files.
  Future<void> _resetAll() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ResetSheet(onBackup: () => _run(() => _export('json'))),
    );
    if (ok != true || !mounted) return;
    final c = FinanceScope.of(context);
    final navigator = Navigator.of(context);
    await c.resetAll();
    await UserFiles.wipe();
    // 1.22: back to the start, where the welcome screens open again; 1.26:
    // without a message on top of them.
    navigator.popUntil((route) => route.isFirst);
  }
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

/// Horizontal gallery of all styles: each tile shows the theme's backdrop
/// gradient, a card and its accent, so a style can be picked by look.
class _StyleGallery extends StatefulWidget {
  const _StyleGallery({
    required this.selected,
    required this.brightness,
    required this.onSelected,
  });
  final String selected;
  final Brightness brightness;
  final ValueChanged<String> onSelected;
  @override
  State<_StyleGallery> createState() => _StyleGalleryState();
}

class _StyleGalleryState extends State<_StyleGallery> {
  static const _tile = 78.0, _gap = 10.0;
  // Opens scrolled so the current style is visible (not always the first).
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: () {
      final index = AppTheme.presetNames.keys.toList().indexOf(widget.selected);
      return index <= 1 ? 0.0 : (index - 1) * (_tile + _gap);
    }(),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final brightness = widget.brightness;
    final onSelected = widget.onSelected;
    final current = Theme.of(context).colorScheme;
    return SizedBox(
      height: 118,
      child: ListView.separated(
        key: const ValueKey('style-gallery'),
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        itemCount: AppTheme.presetNames.length,
        separatorBuilder: (_, _) => const SizedBox(width: _gap),
        itemBuilder: (context, index) {
          final id = AppTheme.presetNames.keys.elementAt(index);
          final theme = AppTheme.build(brightness, id);
          final b = theme.extension<FinanceBackdrop>()!;
          final scheme = theme.colorScheme;
          final active = id == selected;
          final name = AppTheme.presetNames[id]!.split(' · ').first;
          return Semantics(
            button: true,
            selected: active,
            label: 'Стиль ${AppTheme.presetNames[id]}',
            child: GestureDetector(
              key: ValueKey('style-$id'),
              onTap: () => onSelected(id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: _tile,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [b.top, b.middle, b.bottom],
                  ),
                  border: Border.all(
                    color: active ? current.primary : scheme.outlineVariant,
                    width: active ? 2.5 : 1,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: current.primary.withValues(alpha: .35),
                            blurRadius: 14,
                          ),
                        ]
                      : const [],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(7),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: scheme.primary,
                              ),
                              child: active
                                  ? Icon(
                                      Icons.check_rounded,
                                      size: 13,
                                      color: scheme.onPrimary,
                                    )
                                  : null,
                            ),
                            const Spacer(),
                            Container(
                              height: 5,
                              width: 34,
                              decoration: BoxDecoration(
                                color: scheme.onSurface.withValues(alpha: .7),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 5,
                              width: 22,
                              decoration: BoxDecoration(
                                color: scheme.tertiary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Confirmation for a full reset: the button works only after «СБРОС» is
/// typed, so it cannot happen by a stray tap.
/// The reset sheet (1.26): what goes, a backup first if wanted, and a
/// swipe to confirm like the iPhone's «slide to power off».
class _ResetSheet extends StatelessWidget {
  const _ResetSheet({required this.onBackup});
  final VoidCallback onBackup;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: Column(
          key: const ValueKey('reset-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.restart_alt_rounded, color: scheme.error),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Начать с чистого листа?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            line(
              Icons.delete_outline_rounded,
              'Удалятся операции, счета, мечты, бюджеты, платежи и фото чеков',
            ),
            line(Icons.palette_outlined, 'Тема, имя и валюта останутся'),
            line(
              Icons.waving_hand_outlined,
              'Затем откроется приветствие, как при первом запуске',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('reset-backup-first'),
              onPressed: onBackup,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Сначала сохранить копию'),
            ),
            const SizedBox(height: 16),
            SwipeToConfirm(
              key: const ValueKey('reset-slider'),
              label: 'Проведите, чтобы сбросить',
              onConfirmed: () =>
                  Future<void>.delayed(const Duration(milliseconds: 250), () {
                    if (context.mounted) Navigator.pop(context, true);
                  }),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }
}
