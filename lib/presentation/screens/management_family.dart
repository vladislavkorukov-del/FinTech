part of 'management.dart';

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    Future<void> edit([Member? member]) async {
      final name = _text(member?.name ?? '');
      await _edit(
        context,
        title: member == null ? 'Новый участник' : 'Участник семьи',
        controllers: [name],
        fields: (_) => [
          _field(name, 'Имя', maxLength: 80),
          if (member?.id == 'me')
            const Text(
              'Основной профиль можно переименовать. Удалить его нельзя: он используется по умолчанию для новых операций.',
            ),
          if (member != null && c.data.members.length == 1)
            const Text(
              'Последнего участника удалить нельзя. Сначала добавьте другого участника.',
            ),
        ],
        save: () => c.mutate(
          (d) => d.copyWith(
            members: [
              ...d.members.where((m) => m.id != member?.id),
              Member(id: member?.id ?? c.id(), name: name.text.trim()),
            ],
          ),
        ),
        delete:
            member == null || member.id == 'me' || c.data.members.length == 1
            ? null
            : () => c.mutate((d) {
                if (d.entries.any((e) => e.memberId == member.id)) {
                  throw const FormatException(
                    'У участника есть операции. Сначала измените участника в этих операциях.',
                  );
                }
                return d.copyWith(
                  members: d.members.where((m) => m.id != member.id).toList(),
                );
              }),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Семейный профиль'),
        actions: [
          IconButton(
            tooltip: 'Добавить участника',
            onPressed: () => edit(),
            icon: const Icon(Icons.person_add_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SurfaceCard(
            child: Text(
              'Общий учёт на этом устройстве. Назначайте участника каждой операции, чтобы понимать личные и семейные расходы. Синхронизация между устройствами пока не подключена.',
            ),
          ),
          const SizedBox(height: 20),
          ...c.data.members.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SurfaceCard(
                onTap: () => edit(m),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        m.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
