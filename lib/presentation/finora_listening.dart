import 'dart:async';

import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../services/finora_ear.dart';
import 'controller.dart';
import 'finora_vocabulary.dart';
import 'haptics.dart';
import 'widgets/finora_orb.dart';
import 'l10n_widgets.dart';

/// «Финора слушает» (1.31): a sheet with Finora and what she hears, word by
/// word, while her own ear listens silently. Returns the hypotheses, empty
/// when nothing was said or the person cancelled.
Future<List<String>> listenWithFinora(BuildContext context) async {
  final vocabulary = FinoraVocabulary.build(FinanceScope.of(context).data);
  final heard = await showModalBottomSheet<List<String>>(
    context: context,
    isDismissible: true,
    enableDrag: false,
    builder: (_) => _ListeningSheet(vocabulary: vocabulary),
  );
  return heard ?? const [];
}

class _ListeningSheet extends StatefulWidget {
  const _ListeningSheet({required this.vocabulary});
  final List<String> vocabulary;
  @override
  State<_ListeningSheet> createState() => _ListeningSheetState();
}

class _ListeningSheetState extends State<_ListeningSheet> {
  StreamSubscription<String>? _partials;
  String _partial = '';
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Haptics.light();
    _partials = FinoraEar.partials.listen((p) {
      if (mounted) setState(() => _partial = p);
    });
    unawaited(_listen());
  }

  Future<void> _listen() async {
    List<String> heard;
    try {
      heard = await FinoraEar.listen(widget.vocabulary);
    } catch (_) {
      heard = const [];
    }
    if (!mounted || _done) return;
    _done = true;
    Haptics.medium();
    Navigator.pop(context, heard);
  }

  @override
  void dispose() {
    unawaited(_partials?.cancel());
    if (!_done) unawaited(FinoraEar.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        key: const ValueKey('finora-listening'),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FinoraCharacter(
              size: 92,
              moods: _partial.isEmpty
                  ? const [FinoraMood.attention]
                  : const [FinoraMood.processing],
            ),
            const SizedBox(height: 14),
            Text(
              'Финора слушает',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Text(
                _partial.isEmpty
                    ? '«Пятёрочка 450», «покажи расходы за июнь»,\n'
                          '«хочу машину за 2 миллиона»'
                    : '«$_partial»',
                key: ValueKey(_partial.isEmpty),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: _partial.isEmpty ? 14 : 19,
                  height: 1.3,
                  color: _partial.isEmpty
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              key: const ValueKey('finora-listening-cancel'),
              onPressed: () {
                _done = true;
                unawaited(FinoraEar.stop());
                Navigator.pop(context, const <String>[]);
              },
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }
}
