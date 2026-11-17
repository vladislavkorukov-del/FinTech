import 'dart:convert';
import 'dart:io';

import 'package:finora/data/demo_data.dart';
import 'package:finora/data/finance_repository.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/classification/merchant_intelligence.dart';
import 'package:finora/features/finora_ai/classification/transaction_classifier.dart';
import 'package:finora/features/finora_ai/memory/personal_memory.dart';
import 'package:finora/features/finora_ai/models/ai_models.dart';
import 'package:finora/features/finora_ai/personalization/feedback.dart';
import 'package:finora/features/finora_ai/repositories/memory_repository.dart';
import 'package:finora/features/finora_ai/responses/response_layer.dart';
import 'package:finora/features/finora_ai/services/finora_ai.dart';
import 'package:finora/features/finora_ai/services/finora_ai_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Finora AI, phase 2: one key per place, merchant profiles and
/// suggestions, classification sources and thresholds, explanations, the
/// AI settings, resetting personalization and the memory in backups.
void main() {
  final now = DateTime(2026, 11, 20, 12);
  const groceries = 'expense-0', cafe = 'expense-1';
  var n = 0;
  FinanceEntry e(
    DateTime d,
    int rub,
    String category, {
    String payee = '',
    String account = 'card',
  }) => FinanceEntry(
    id: 'q${n++}',
    kind: EntryKind.expense,
    amountMinor: rub * 100,
    currency: 'RUB',
    accountId: account,
    categoryId: category,
    payee: payee,
    date: d,
  );

  FinanceData data(List<FinanceEntry> entries, {AiSettings? ai}) {
    final demo = createDemoData(now);
    return demo.copyWith(
      entries: entries,
      preferences: demo.preferences.copyWith(ai: ai),
    );
  }

  group('merchants', () {
    test('a bank\'s and a person\'s spellings are one place', () {
      final k = MerchantIntelligence.canonicalKey;
      expect(k('PYATEROCHKA #123'), k('Пятерочка'));
      expect(k('X5 PYATEROCHKA'), k('Пятёрочка'));
      expect(k('VKUSVILL 23'), k('ВкусВилл'));
      // Unknown places: legal forms and store numbers are dropped.
      expect(k('ООО Ромашка 4512'), k('ромашка'));
      expect(k('Кофейня №1 #77'), k('Кофейня №1'));
      expect(k(''), '');
    });

    test('a profile: usual category, typical sum, range, last account', () {
      final entries = [
        for (var i = 0; i < 8; i++)
          e(
            DateTime(2026, 10, 1 + i * 3),
            1000 + i * 100,
            groceries,
            payee: i.isEven ? 'PYATEROCHKA #12' : 'Пятёрочка',
            account: i == 7 ? 'cash' : 'card',
          ),
        e(DateTime(2026, 10, 5), 300, cafe, payee: 'Пятёрочка'),
      ];
      final p = MerchantIntelligence.profileOf(data(entries), 'Пятерочка')!;
      expect(p.name, 'Пятёрочка');
      expect(p.count, 9);
      expect(p.usualCategoryId, groceries);
      expect(p.categoryShare, closeTo(8 / 9, .01));
      expect(p.aliases, containsAll(['PYATEROCHKA #12', 'Пятёрочка']));
      expect(p.lowAmount, lessThanOrEqualTo(p.typicalAmount));
      expect(p.highAmount, greaterThanOrEqualTo(p.typicalAmount));
      expect(p.lastAccountId, 'cash');
    });

    test('suggestions while typing: two letters, frequent first', () {
      final d = data([
        for (var i = 0; i < 6; i++)
          e(DateTime(2026, 11, 1 + i), 400, cafe, payee: 'Шоколадница'),
        e(DateTime(2026, 11, 2), 900, cafe, payee: 'Шаурма у дома'),
      ]);
      expect(MerchantIntelligence.suggest(d, 'ш'), isEmpty);
      final hits = MerchantIntelligence.suggest(d, 'ша');
      expect(hits.first.name, 'Шаурма у дома');
      final shoko = MerchantIntelligence.suggest(d, 'шо');
      expect(shoko.single.name, 'Шоколадница');
      expect(shoko.single.typicalAmount, 40000);
    });
  });

  group('classification', () {
    test('history by canonical key: a bank spelling learns from the name', () {
      final d = data([
        for (var i = 0; i < 4; i++)
          e(DateTime(2026, 11, 1 + i), 500, cafe, payee: 'Ромашка'),
      ]);
      final r = const TransactionClassifier().classify(
        merchant: 'ООО РОМАШКА 4512',
        amountMinor: 50000,
        kind: EntryKind.expense,
        data: d,
      );
      expect(r.best!.categoryId, cafe);
      expect(r.best!.source, ClassificationSource.history);
      expect(r.best!.evidence, 4);
    });

    test('an exact rule: the payee is a category\'s name', () {
      final d = data(const []);
      final taxi = d.categories.firstWhere(
        (c) => c.kind == EntryKind.expense && !c.archived,
      );
      final r = const TransactionClassifier().classify(
        merchant: taxi.name,
        amountMinor: 100,
        kind: EntryKind.expense,
        data: d,
      );
      expect(r.top.first.categoryId, taxi.id);
      expect(r.top.first.source, ClassificationSource.exact);
    });

    test('a fallback fills three choices but is never enough to apply', () {
      final d = data([
        for (var i = 0; i < 3; i++)
          e(DateTime(2026, 11, 1 + i), 500, cafe, payee: 'Кафе $i'),
        e(DateTime(2026, 11, 5), 500, groceries, payee: 'Рынок'),
      ]);
      final r = const TransactionClassifier().classify(
        merchant: 'zzqq',
        amountMinor: 100,
        kind: EntryKind.expense,
        data: d,
      );
      expect(r.best, isNull);
      expect(r.top, isNotEmpty);
      expect(r.top.first.source, ClassificationSource.fallback);
      expect(
        AiConfig.decide(r, AiAutomation.automatic),
        CategoryDecision.choose,
      );
    });

    test('decisions follow the thresholds and the automation level', () {
      ClassificationResult at(double c) => ClassificationResult(
        top: [CategoryScore('x', c, ClassificationSource.history)],
      );
      expect(
        AiConfig.decide(at(.9), AiAutomation.smart),
        CategoryDecision.apply,
      );
      expect(
        AiConfig.decide(at(.6), AiAutomation.smart),
        CategoryDecision.suggest,
      );
      expect(
        AiConfig.decide(at(.3), AiAutomation.smart),
        CategoryDecision.choose,
      );
      expect(
        AiConfig.decide(at(.95), AiAutomation.suggestOnly),
        CategoryDecision.suggest,
      );
      expect(
        AiConfig.decide(at(.6), AiAutomation.automatic),
        CategoryDecision.apply,
      );
      expect(
        AiConfig.decide(
          const ClassificationResult(top: []),
          AiAutomation.smart,
        ),
        CategoryDecision.none,
      );
    });

    test('an explanation names the reason and the evidence', () {
      final d = data([
        for (var i = 0; i < 8; i++)
          e(DateTime(2026, 11, 1 + i), 500, groceries, payee: 'ВкусВилл'),
      ]);
      final s = FinoraAiSnapshot.compute(d, now: now);
      final r = const TransactionClassifier().classify(
        merchant: 'ВкусВилл',
        amountMinor: 50000,
        kind: EntryKind.expense,
        data: d,
      );
      final text = ResponseLayer.classification(s, 'ВкусВилл', r);
      expect(text, contains('Последние 8 покупок'));
    });

    test('memory outweighs history and old keys are still read', () {
      final memory = PersonalMemory();
      // An older memory kept the plain name as the key.
      memory.observe('ромашка', groceries);
      memory.observe('ромашка', groceries);
      final d = data([e(DateTime(2026, 11, 1), 500, cafe, payee: 'Ромашка')]);
      final r = const TransactionClassifier().classify(
        merchant: 'Ромашка',
        amountMinor: 50000,
        kind: EntryKind.expense,
        data: d,
        memory: memory,
      );
      expect(r.best!.categoryId, groceries);
      expect(r.best!.source, ClassificationSource.memory);
    });
  });

  group('settings and memory', () {
    test('AI settings survive a save; older saves get the defaults', () {
      const ai = AiSettings(
        autoCategorize: false,
        personalization: false,
        automation: AiAutomation.suggestOnly,
      );
      final back = AppPreferences.fromJson(
        const AppPreferences(ai: ai).toJson(),
      ).ai;
      expect(back.autoCategorize, isFalse);
      expect(back.personalization, isFalse);
      expect(back.automation, AiAutomation.suggestOnly);
      final old = AppPreferences.fromJson(const {}).ai;
      expect(old.enabled, isTrue);
      expect(old.automation, AiAutomation.smart);
    });

    test('without personalization the memory is not used', () {
      final ai = FinoraAi(memory: MemoryRepository());
      final key = MerchantIntelligence.canonicalKey('Ромашка');
      ai.memory.observe(key, groceries);
      ai.memory.observe(key, groceries);
      final on = ai.classify(data(const []), merchant: 'Ромашка');
      expect(on.best?.source, ClassificationSource.memory);
      final off = ai.classify(
        data(const [], ai: const AiSettings(personalization: false)),
        merchant: 'Ромашка',
      );
      expect(
        off.top.any((t) => t.source == ClassificationSource.memory),
        isFalse,
      );
    });

    test('reset forgets what was learned; restore brings it back', () async {
      final dir = await Directory.systemTemp.createTemp('finora-ai-mem-');
      addTearDown(() => dir.delete(recursive: true));
      final ai = FinoraAi(
        memory: MemoryRepository(file: File('${dir.path}/m.json')),
      );
      await ai.ready();
      Feedback.observeSave(
        ai.memory,
        e(DateTime(2026, 11, 1), 500, cafe, payee: 'Ромашка'),
      );
      ai.memory.snooze('anomaly:x', now: now);
      final saved = ai.memoryForBackup();
      expect(ai.memory.merchants, isNotEmpty);
      await ai.resetPersonalization();
      expect(ai.memory.merchants, isEmpty);
      expect(ai.memory.snoozed, isEmpty);
      await ai.restoreMemory(saved);
      expect(ai.memory.merchants, isNotEmpty);
      // Written to the file at once.
      final onDisk = jsonDecode(
        await File('${dir.path}/m.json').readAsString(),
      );
      expect((onDisk as Map)['merchants'], isNotEmpty);
    });

    test('the full copy carries the memory and still imports', () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('finora-ai-backup-');
      addTearDown(() => dir.delete(recursive: true));
      final repo = await FinanceRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/db',
      );
      addTearDown(repo.close);
      await repo.save(createDemoData(now));
      final json = await repo.exportJson(
        extra: {
          'aiMemory': {'version': 2, 'merchants': <String, Object?>{}},
        },
      );
      expect((jsonDecode(json) as Map)['aiMemory'], isA<Map>());
      await repo.importJson(json);
      expect((await repo.load()).entries, isNotEmpty);
    });
  });
}
