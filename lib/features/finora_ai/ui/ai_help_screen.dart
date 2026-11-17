import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../../../presentation/l10n_widgets.dart';
import '../../../presentation/widgets/finora_orb.dart';
import '../../../presentation/widgets/grouped_list.dart';
import '../responses/capabilities.dart';
import 'finora_ai_screen.dart';

/// «Finora AI» in Settings: what she can do, with questions to try — the
/// same list the chat gives for «что ты умеешь?». Tapping a question opens
/// the chat and asks it.
class AiHelpScreen extends StatelessWidget {
  const AiHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Finora AI')),
      body: ListView(
        key: const ValueKey('ai-help'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            children: [
              const FinoraMark(size: 56, mood: FinoraMood.happy),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Финора считает по твоим операциям прямо на телефоне — '
                  'без интернета, ничего не отправляя. Нажми на вопрос, и '
                  'она ответит в чате.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final c in AiCapabilities.all)
            GroupedSection(
              title: c.title,
              footer: c.about,
              children: [
                for (final q in c.examples)
                  GroupedRow(
                    key: ValueKey('ai-help-$q'),
                    icon: c.icon,
                    color: TileColors.orange,
                    title: '«$q»',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => FinoraAiScreen(initialQuestion: q),
                      ),
                    ),
                  ),
              ],
            ),
          const GroupedSection(
            title: 'Как она отвечает',
            footer:
                'Если данных мало, Финора так и скажет — она не придумывает '
                'суммы и прогнозы.',
            children: [
              GroupedRow(
                icon: Icons.calculate_outlined,
                color: TileColors.blue,
                title: 'Сначала факты, потом слова',
                subtitle: 'Все числа — из твоих операций',
              ),
              GroupedRow(
                icon: Icons.school_outlined,
                color: TileColors.green,
                title: 'Учится на исправлениях',
                subtitle: 'Поменял категорию — в следующий раз она запомнит',
              ),
              GroupedRow(
                icon: Icons.lock_outline_rounded,
                color: TileColors.indigo,
                title: 'Всё остаётся на телефоне',
                subtitle: 'Операции и память Финоры никуда не уходят',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
