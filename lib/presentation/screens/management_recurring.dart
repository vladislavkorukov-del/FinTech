part of 'management.dart';

const frequencyNames = {
  'daily': 'Ежедневно',
  'weekly': 'Еженедельно',
  'monthly': 'Ежемесячно',
  'yearly': 'Ежегодно',
  'custom': 'Свой интервал в днях',
};

const _reminderLeadNames = <int, String>{
  0: 'В день платежа',
  1: 'За 1 день',
  3: 'За 3 дня',
  7: 'За 7 дней',
};

const paymentTypeNames = {
  'subscription': 'Подписка',
  'mandatory': 'Обязательный платёж',
};

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key, this.initialPaymentType});
  final String? initialPaymentType;
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  late String filter =
      const ['subscription', 'mandatory'].contains(widget.initialPaymentType)
      ? widget.initialPaymentType!
      : 'all';

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final rules = [...c.data.recurring]
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    final subscriptions = rules
        .where(
          (r) => r.kind == EntryKind.expense && r.paymentType == 'subscription',
        )
        .toList();
    final mandatory = rules
        .where(
          (r) => r.kind == EntryKind.expense && r.paymentType == 'mandatory',
        )
        .toList();
    final incomes = rules.where((r) => r.kind == EntryKind.income).toList();
    final shown = filter == 'subscription'
        ? subscriptions
        : filter == 'mandatory'
        ? mandatory
        : filter == 'income'
        ? incomes
        : rules;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          // 1.33: one place for subscriptions, loans and other payments.
          filter == 'subscription'
              ? 'Подписки'
              : filter == 'mandatory'
              ? 'Обязательные платежи'
              : 'Платежи и подписки',
        ),
        actions: [
          IconButton(
            tooltip: filter == 'subscription'
                ? 'Добавить подписку'
                : filter == 'income'
                ? 'Добавить регулярный доход'
                : 'Добавить платёж',
            key: const ValueKey('payments-add'),
            onPressed: () => filter == 'all'
                ? _chooseAndAdd(context)
                : showRecurringEditor(
                    context,
                    paymentType: filter == 'subscription'
                        ? 'subscription'
                        : 'mandatory',
                    initialKind: filter == 'income'
                        ? EntryKind.income
                        : EntryKind.expense,
                  ),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                const {
                      'all': 'Все',
                      'subscription': 'Подписки',
                      'mandatory': 'Обязательные',
                      'income': 'Доходы',
                    }.entries
                    .map(
                      (entry) => ChoiceChip(
                        key: ValueKey('payment-filter-${entry.key}'),
                        label: Text(entry.value),
                        selected: filter == entry.key,
                        onSelected: (_) => setState(() => filter = entry.key),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            EmptyState(
              filter == 'subscription'
                  ? 'Подписок пока нет'
                  : filter == 'mandatory'
                  ? 'Нет обязательных платежей'
                  : filter == 'income'
                  ? 'Запланируйте доход'
                  : 'Нет регулярных операций',
              filter == 'subscription'
                  ? 'Добавьте сервис, выберите сумму и дату следующего продления.'
                  : filter == 'income'
                  ? 'Добавьте зарплату, проценты или другой регулярный доход.'
                  : 'Добавьте платёж, сумму и дату.',
            ),
          if ((filter == 'all' || filter == 'subscription') &&
              subscriptions.isNotEmpty) ...[
            const SectionTitle('Подписки'),
            ...subscriptions.map((r) => _ruleCard(context, c, r)),
          ],
          if ((filter == 'all' || filter == 'mandatory') &&
              mandatory.isNotEmpty) ...[
            const SectionTitle('Обязательные платежи'),
            ...mandatory.map((r) => _ruleCard(context, c, r)),
          ],
          if ((filter == 'all' || filter == 'income') &&
              incomes.isNotEmpty) ...[
            const SectionTitle('Регулярные доходы'),
            ...incomes.map((r) => _ruleCard(context, c, r)),
          ],
        ],
      ),
    );
  }

  /// «+» on the common list: which kind to add.
  Future<void> _chooseAndAdd(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (id, icon, title, subtitle) in const [
              (
                'subscription',
                Icons.subscriptions_outlined,
                'Подписка',
                'Сервисы, музыка, связь, кино',
              ),
              (
                'mandatory',
                Icons.receipt_long_outlined,
                'Обязательный платёж',
                'Кредит, ипотека, аренда, коммуналка',
              ),
              (
                'income',
                Icons.south_west_rounded,
                'Регулярный доход',
                'Зарплата, аванс, проценты',
              ),
            ])
              ListTile(
                key: ValueKey('payments-add-$id'),
                leading: Icon(icon),
                title: Text(title),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(ctx, id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    await showRecurringEditor(
      context,
      paymentType: choice == 'income' ? 'mandatory' : choice,
      initialKind: choice == 'income' ? EntryKind.income : EntryKind.expense,
    );
  }

  // 1.28: swipe left to delete a subscription or payment.
  Widget _ruleCard(
    BuildContext context,
    FinanceController c,
    RecurringRule r,
  ) => SwipeToDelete(
    key: ValueKey('swipe-rule-${r.id}'),
    title: 'Удалить «${r.name}»?',
    message:
        'Платёж больше не будет напоминать о себе. Уже записанные '
        'операции останутся.',
    onDelete: () async {
      await c.mutate(
        (d) => d.copyWith(
          recurring: d.recurring.where((x) => x.id != r.id).toList(),
        ),
      );
    },
    child: _ruleCardBody(context, c, r),
  );

  Widget _ruleCardBody(
    BuildContext context,
    FinanceController c,
    RecurringRule r,
  ) => Padding(
    key: ValueKey('payment-rule-${r.id}'),
    padding: const EdgeInsets.only(bottom: 12),
    child: SurfaceCard(
      onTap: () => showRecurringEditor(context, rule: r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (r.kind == EntryKind.expense &&
                  (r.paymentType == 'subscription' ||
                      r.icon != null ||
                      r.serviceId != null ||
                      r.customIconPath != null))
                ServiceBadge(
                  serviceId: r.serviceId,
                  customIconPath: r.customIconPath,
                  name: r.name,
                  icon: r.icon,
                  iconColor: r.color,
                )
              else
                CategoryBadge(
                  category: c.category(r.categoryId),
                  icon: r.kind == EntryKind.income
                      ? Icons.south_west_rounded
                      : null,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${DateFormat('d MMM', 'ru').format(r.nextDate)} · ${frequencyNames[r.frequency] ?? r.frequency}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            money(r.amountMinor, r.currency),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 5),
          Text(
            r.enabled
                ? (r.automatic
                      ? 'Автоматическая операция при запуске'
                      : 'Вручную')
                : 'Приостановлен',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 5),
          Text(
            !r.enabled
                ? 'Напоминание приостановлено'
                : r.reminderEnabled
                ? c.data.preferences.notifications
                      ? 'Напоминание: ${_reminderLeadNames[r.reminderDaysBefore] ?? 'в день платежа'}, ${r.reminderHour.toString().padLeft(2, '0')}:${r.reminderMinute.toString().padLeft(2, '0')}'
                      : 'Напоминание отключено в настройках'
                : 'Без напоминания',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

Future<void> showRecurringEditor(
  BuildContext context, {
  RecurringRule? rule,
  String? paymentType,
  EntryKind initialKind = EntryKind.expense,
}) async {
  final c = FinanceScope.of(context);
  final accounts = c.data.accounts.where((a) => !a.archived).toList();
  if (accounts.isEmpty) {
    showError(context, const FormatException('Сначала добавьте счёт.'));
    return;
  }
  final name = _text(rule?.name ?? '');
  final amount = _text(rule == null ? '' : _amount(rule.amountMinor));
  final interval = _text('${rule?.interval ?? 1}');
  var serviceId = rule?.serviceId;
  var customIconPath = rule?.customIconPath;
  // 1.34: or an icon from the app's standard set.
  var icon = rule?.icon;
  var iconColor = rule?.color;
  var reminderEnabled = rule?.reminderEnabled ?? false;
  var reminderDaysBefore = rule?.reminderDaysBefore ?? 1;
  var reminderTime = TimeOfDay(
    hour: rule?.reminderHour ?? 10,
    minute: rule?.reminderMinute ?? 0,
  );
  var requestingPermission = false;
  var kind = rule?.kind ?? initialKind;
  var selectedPaymentType =
      rule?.paymentType ??
      (paymentType == 'subscription' ? 'subscription' : 'mandatory');
  if (kind == EntryKind.income) {
    selectedPaymentType = 'mandatory';
  }
  var account = rule?.accountId ?? accounts.first.id;
  var category =
      rule?.categoryId ??
      c.data.categories
          .where((a) => a.kind == kind && !a.archived)
          .firstOrNull
          ?.id ??
      '';
  var frequency = rule?.frequency ?? 'monthly';
  var next = rule?.nextDate ?? DateTime.now().add(const Duration(days: 1));
  var anchorDay = rule?.anchorDay ?? next.day;
  var automatic = rule?.automatic ?? false;
  var enabled = rule?.enabled ?? true;
  await _edit(
    context,
    title: rule == null
        ? selectedPaymentType == 'subscription'
              ? 'Новая подписка'
              : 'Новая регулярная операция'
        : 'Регулярная операция',
    controllers: [name, amount, interval],
    fields: (set) => [
      if (kind == EntryKind.expense)
        Builder(
          builder: (serviceContext) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                key: const ValueKey('choose-subscription-service'),
                contentPadding: EdgeInsets.zero,
                leading: ServiceBadge(
                  serviceId: serviceId,
                  customIconPath: customIconPath,
                  name: name.text,
                  icon: icon,
                  iconColor: iconColor,
                ),
                title: Text(
                  customIconPath != null
                      ? 'Своя иконка'
                      : icon != null
                      ? 'Иконка из набора'
                      : ServiceCatalog.byId(serviceId)?.name ??
                            'Выбрать сервис',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final choice = await showServicePicker(serviceContext);
                  if (choice != null && serviceContext.mounted) {
                    set(() {
                      serviceId = choice.serviceId;
                      customIconPath = choice.customIconPath;
                      icon = null;
                      iconColor = null;
                      name.text = choice.name;
                    });
                  }
                },
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    key: const ValueKey('recurring-standard-icon'),
                    icon: const Icon(Icons.category_outlined),
                    label: const Text('Из набора'),
                    onPressed: () async {
                      final picked = await showIconPicker(
                        serviceContext,
                        icon: icon ?? 26,
                        color:
                            iconColor ??
                            c.category(category)?.color ??
                            categoryColors.first,
                      );
                      if (picked != null && serviceContext.mounted) {
                        set(() {
                          icon = picked.$1;
                          iconColor = picked.$2;
                          customIconPath = null;
                          serviceId = null;
                        });
                      }
                    },
                  ),
                  TextButton.icon(
                    key: const ValueKey('upload-recurring-icon'),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Своя иконка'),
                    onPressed: () async {
                      try {
                        final path = await pickServiceIcon();
                        if (path != null && serviceContext.mounted) {
                          set(() {
                            customIconPath = path;
                            icon = null;
                            iconColor = null;
                          });
                        }
                      } catch (e) {
                        if (serviceContext.mounted) {
                          showError(serviceContext, e);
                        }
                      }
                    },
                  ),
                  if (serviceId != null ||
                      customIconPath != null ||
                      icon != null)
                    TextButton(
                      onPressed: () => set(() {
                        serviceId = null;
                        customIconPath = null;
                        icon = null;
                        iconColor = null;
                      }),
                      child: const Text('Убрать иконку'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      _field(name, 'Название', maxLength: 80),
      _select(
        'Тип',
        kind,
        const {EntryKind.expense: 'Расход', EntryKind.income: 'Доход'},
        (v) => set(() {
          kind = v;
          if (kind == EntryKind.income) {
            selectedPaymentType = 'mandatory';
          }
          category =
              c.data.categories
                  .where((a) => a.kind == kind && !a.archived)
                  .firstOrNull
                  ?.id ??
              '';
        }),
      ),
      if (kind == EntryKind.expense)
        _select(
          'Вид платежа',
          selectedPaymentType,
          paymentTypeNames,
          (v) => set(() => selectedPaymentType = v),
        ),
      _field(amount, 'Сумма', amount: true),
      _select('Счёт', account, {
        for (final a in c.data.accounts.where(
          (a) => !a.archived || a.id == account,
        ))
          a.id: '${a.name} · ${a.currency}',
      }, (v) => set(() => account = v)),
      _select('Категория', category, {
        if (!c.data.categories.any(
          (a) => a.kind == kind && (!a.archived || a.id == rule?.categoryId),
        ))
          '': 'Сначала создайте категорию',
        for (final a in c.data.categories.where(
          (a) => a.kind == kind && (!a.archived || a.id == rule?.categoryId),
        ))
          a.id: a.archived ? '${a.name} · Архив' : a.name,
      }, (v) => set(() => category = v)),
      _select(
        'Повтор',
        frequency,
        frequencyNames,
        (v) => set(() => frequency = v),
      ),
      _field(
        interval,
        frequency == 'custom'
            ? 'Каждые N дней'
            : 'Интервал (1 = каждый период)',
        amount: true,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.calendar_today_outlined),
        title: Text('Следующий: ${_date(next, c)}'),
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: next,
            firstDate: DateTime(1900),
            lastDate: DateTime(2200),
          );
          if (d != null) {
            set(() {
              next = d;
              anchorDay = d.day;
            });
          }
        },
      ),
      Builder(
        builder: (reminderContext) {
          final current = FinanceScope.of(reminderContext);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile.adaptive(
                key: const ValueKey('recurring-reminder-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Напоминание о платеже'),
                subtitle: const Text('Уведомление на этом устройстве'),
                value: reminderEnabled,
                onChanged: requestingPermission
                    ? null
                    : (value) async {
                        if (!value) {
                          set(() => reminderEnabled = false);
                          return;
                        }
                        set(() => requestingPermission = true);
                        try {
                          final allowed = await c.notifications
                              .requestPermission();
                          if (!reminderContext.mounted) {
                            return;
                          }
                          if (!allowed) {
                            showError(
                              reminderContext,
                              const FormatException(
                                'Разрешите уведомления Finora в настройках Android.',
                              ),
                            );
                            return;
                          }
                          set(() => reminderEnabled = true);
                        } catch (e) {
                          if (reminderContext.mounted) {
                            showError(reminderContext, e);
                          }
                        } finally {
                          if (reminderContext.mounted) {
                            set(() => requestingPermission = false);
                          }
                        }
                      },
              ),
              if (reminderEnabled) ...[
                KeyedSubtree(
                  key: const ValueKey('recurring-reminder-lead'),
                  child: _select(
                    'Когда напомнить',
                    reminderDaysBefore,
                    _reminderLeadNames,
                    (value) => set(() => reminderDaysBefore = value),
                  ),
                ),
                ListTile(
                  key: const ValueKey('recurring-reminder-time'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_rounded),
                  title: const Text('Время напоминания'),
                  trailing: Text(reminderTime.format(reminderContext)),
                  onTap: () async {
                    final selected = await showTimePicker(
                      context: reminderContext,
                      initialTime: reminderTime,
                      initialEntryMode: TimePickerEntryMode.input,
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(alwaysUse24HourFormat: true),
                        child: child!,
                      ),
                    );
                    if (selected != null && reminderContext.mounted) {
                      set(() => reminderTime = selected);
                    }
                  },
                ),
                if (!current.data.preferences.notifications) ...[
                  const Text('Уведомления отключены в настройках приложения.'),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () async {
                        await Navigator.push(
                          reminderContext,
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                        if (reminderContext.mounted) {
                          set(() {});
                        }
                      },
                      child: const Text('Настройки уведомлений'),
                    ),
                  ),
                ],
              ],
            ],
          );
        },
      ),
      SwitchListTile.adaptive(
        key: const ValueKey('recurring-automatic-switch'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Автоматически создавать операцию'),
        subtitle: const Text('При следующем запуске в день платежа или позже.'),
        value: automatic,
        onChanged: (v) => set(() => automatic = v),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Активен'),
        value: enabled,
        onChanged: (v) => set(() => enabled = v),
      ),
    ],
    save: () async {
      // 1.27: «чат гпт» typed as the name is ChatGPT, with its logo.
      if (serviceId == null && customIconPath == null && icon == null) {
        final spoken = ServiceRecognizer.find(name.text, whole: true);
        if (spoken != null && !ServiceCatalog.banks.contains(spoken)) {
          serviceId = spoken.id;
          name.text = spoken.name;
        }
      }
      final n = int.tryParse(interval.text);
      final m = FinanceEngine.parseMinor(amount.text);
      if (category.isEmpty) {
        throw const FormatException(
          'Сначала создайте категорию для этого типа операции.',
        );
      }
      if (n == null || n < 1 || n > 3650 || m <= 0) {
        throw const FormatException('Проверьте сумму и интервал от 1 до 3650.');
      }
      await c.saveRecurring(
        RecurringRule(
          id: rule?.id ?? c.id(),
          name: name.text.trim(),
          serviceId: kind == EntryKind.expense ? serviceId : null,
          customIconPath: kind == EntryKind.expense ? customIconPath : null,
          icon: kind == EntryKind.expense ? icon : null,
          color: kind == EntryKind.expense ? iconColor : null,
          reminderEnabled: reminderEnabled,
          reminderDaysBefore: reminderDaysBefore,
          reminderHour: reminderTime.hour,
          reminderMinute: reminderTime.minute,
          accountId: account,
          currency: c.account(account)!.currency,
          categoryId: category.isEmpty ? null : category,
          kind: kind,
          paymentType: kind == EntryKind.income
              ? rule?.paymentType ?? 'mandatory'
              : selectedPaymentType,
          amountMinor: m,
          interval: n,
          frequency: frequency,
          nextDate: next,
          anchorDay: anchorDay,
          automatic: automatic,
          enabled: enabled,
        ),
      );
      final result = await c.waitForNotificationSync();
      if (!result.succeeded && context.mounted) {
        showError(context, const FormatException(notificationSyncWarning));
      }
      // Returning closes the shared editor after the committed save, including
      // when scheduling failed. A retry must not create a second financial rule.
    },
    delete: rule == null
        ? null
        : () async {
            await c.mutate(
              (d) => d.copyWith(
                recurring: d.recurring.where((r) => r.id != rule.id).toList(),
              ),
            );
            final result = await c.waitForNotificationSync();
            if (!result.succeeded && context.mounted) {
              showError(
                context,
                const FormatException(notificationSyncWarning),
              );
            }
          },
  );
}
