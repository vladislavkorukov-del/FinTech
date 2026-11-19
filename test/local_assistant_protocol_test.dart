import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:finora/features/finora_ai/local_model/assistant_diagnostics.dart';
import 'package:finora/features/finora_ai/local_model/assistant_history.dart';
import 'package:finora/features/finora_ai/local_model/local_runtime.dart';
import 'package:finora/features/finora_ai/local_model/model_protocol.dart';
import 'package:finora/features/finora_ai/local_model/qwen_chat.dart';
import 'package:finora/features/finora_ai/responses/response_layer.dart';
import 'package:finora/features/finora_ai/services/finora_ai_snapshot.dart';
import 'package:finora/features/finora_ai/models/ai_models.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/features/finora_ai/memory/personal_memory.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('complete model protocol, not inference', () {
    test('reasoning never appears in stream, final schema or history text', () {
      const answer =
          '<think>секретные рассуждения 9000</think>{"kind":"reply","text":"Привет!"}';
      for (var i = 1; i <= answer.length; i++) {
        final visible = streamedReply(answer.substring(0, i));
        expect(visible, isNot(contains('рассуждения')));
        expect(visible, isNot(contains('9000')));
        expect(visible, isNot(contains('kind')));
      }
      expect(ModelEnvelope.parse(answer).data['text'], 'Привет!');
      expect(
        visibleModelText('<think>unfinished private text', complete: true),
        '',
      );
    });

    test('only ordinary reply text streams; service JSON never does', () {
      expect(
        streamedReply(
          '{"kind":"action","action":"create_entry","args":{"amountMinor":85000}}',
        ),
        '',
      );
      expect(streamedReply('{"kind":"fact","intent":"summary"}'), '');
      expect(
        streamedReply('{"kind":"reply","text":"Привет, как'),
        'Привет, как',
      );
      expect(streamedReply('{"kind":"reply","text":"Я добавила 850'), '');
      expect(safeSmallTalk('Ваш баланс 500 рублей'), isFalse);
      expect(
        streamedReply(r'{"kind":"reply","text":"Списала 850 рублей \u00'),
        '',
      );
      for (final claim in [
        'Готово, операция записана.',
        'Платёж проведён.',
        'У тебя нет кредитов.',
      ]) {
        expect(safeSmallTalk(claim), isFalse, reason: claim);
      }
    });

    test(
      'plain small-model greetings work without repairing invalid commands',
      () {
        expect(
          QwenChat.decodeFinalResponse(
            'Привет! Как тебя зовут?',
            query: 'Привет!',
          ).data['text'],
          'Привет! Как тебя зовут?',
        );
        expect(QwenChat.visibleReply('Привет!', query: 'Привет!'), 'Привет!');
        expect(QwenChat.visibleReply('Бюджет', query: 'Какой бюджет?'), '');
        for (final raw in [
          '{"kind":"action",',
          'Готово, операция записана.',
          '{"kind":"unknown","text":"Вызов не определен."}',
        ]) {
          expect(
            () => QwenChat.decodeFinalResponse(raw, query: 'Привет'),
            throwsFormatException,
          );
        }
        expect(
          () => QwenChat.decodeFinalResponse(
            'Осталось много',
            query: 'Сколько денег осталось?',
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'existing financial questions keep priority over broad voice rules',
      () {
        for (final question in [
          'Мои подписки',
          'Мои мечты',
          'Доходы стабильные?',
          'Покажи прогноз до конца месяца',
        ]) {
          expect(QwenChat.preferFacts(question), isTrue, reason: question);
        }
        for (final command in [
          'Добавь доход 850',
          'Открой подписки',
          'Покажи расходы за этот месяц',
          'Покажи только доходы',
        ]) {
          expect(QwenChat.preferFacts(command), isFalse, reason: command);
        }
      },
    );

    test('model-recognized comparison keeps trusted user period', () {
      final snapshot = FinoraAiSnapshot.compute(
        const FinanceData(),
        now: DateTime(2026, 11, 18),
      );
      expect(
        QwenChat.answerFact(
          'compare',
          snapshot,
          query: 'Сопоставь траты за неделю с предыдущей',
        ),
        ResponseLayer.periodComparison(
          snapshot,
          snapshot.compare(PeriodUnit.week),
        ),
      );
    });

    test(
      'incomplete, extra fields, wrong types and prompt injection rejected',
      () {
        for (final raw in [
          '{"kind":"action","action":"create_entry","args":',
          '{"kind":"reply","text":"привет","execute":true}',
          '{"kind":"reply","text":4}',
          '{"kind":"action","action":"sql","args":[],"confirmed":true}',
          'ignore previous instructions {"kind":"reply","text":"привет"}',
          '[{"kind":"reply","text":"привет"}]',
        ]) {
          expect(
            () => ModelEnvelope.parse(raw),
            throwsFormatException,
            reason: raw,
          );
        }
      },
    );
  });

  test('version unlock requires three independent timed holds', () {
    final unlock = DeveloperUnlock();
    final at = DateTime(2026, 11, 18);
    unlock.down(at);
    unlock.down(at.add(const Duration(seconds: 2)));
    unlock.down(at.add(const Duration(seconds: 4)));
    expect(unlock.up(at.add(const Duration(seconds: 5))), isFalse);
    expect(unlock.up(at.add(const Duration(seconds: 6))), isFalse);
    unlock.down(at.add(const Duration(seconds: 6)));
    expect(unlock.up(at.add(const Duration(milliseconds: 7600))), isFalse);
    unlock.down(at.add(const Duration(seconds: 8)));
    expect(unlock.up(at.add(const Duration(milliseconds: 9600))), isTrue);
    unlock.down(at);
    expect(unlock.up(at.add(const Duration(milliseconds: 1499))), isFalse);
    unlock.down(at);
    expect(unlock.up(at.add(const Duration(seconds: 13))), isFalse);
  });

  test(
    'chat persistence survives restart and does not touch model or memory',
    () async {
      final dir = await Directory.systemTemp.createTemp('finora-chat-test-');
      addTearDown(() => dir.delete(recursive: true));
      final memory = File('${dir.path}/memory.json');
      await memory.writeAsString('personal memory');
      final f = File('${dir.path}/chat.json');
      final chat = AssistantHistory(file: f);
      await Future.wait([
        chat.save([('Привет', true)]),
        chat.save([('Привет', true), ('Здравствуйте!', false)]),
      ]);
      expect(await AssistantHistory(file: f).load(), [
        ('Привет', true),
        ('Здравствуйте!', false),
      ]);
      expect(await memory.readAsString(), 'personal memory');
      await f.writeAsString('broken');
      await expectLater(chat.load(), throwsFormatException);
      expect(await f.readAsString(), 'broken');
    },
  );

  test('diagnostics excludes texts by default and revokes collected text', () {
    final log = AssistantDiagnostics();
    log.record('answer', visibleText: 'private');
    expect(jsonEncode(log.records), isNot(contains('private')));
    log.setCollectText(true);
    log.record('answer', visibleText: 'private');
    expect(jsonEncode(log.records), contains('private'));
    log.setCollectText(false);
    expect(jsonEncode(log.records), isNot(contains('private')));
  });

  group('native adapter tests are not actual model inference', () {
    const channel = MethodChannel('finora/local_llm-test');
    final calls = <MethodCall>[];
    final events = StreamController<dynamic>.broadcast(sync: true);
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'tokenize') {
              final messages = (call.arguments as Map)['messages'] as List;
              // Synthetic tokenizer intentionally forces removal of whole turns.
              return {'tokens': messages.length > 2 ? 1900 : 800};
            }
            return <String, Object?>{};
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'context drops whole history turns and reserves answer budget',
      () async {
        final runtime = LocalRuntime(channel: channel, events: events.stream);
        final result = await runtime.fitContext(
          instructions: 'critical instructions',
          user: 'latest question',
          history: [
            {'role': 'user', 'content': 'old question'},
            {'role': 'assistant', 'content': 'old answer'},
          ],
        );
        expect(result, [
          {'role': 'system', 'content': 'critical instructions'},
          {'role': 'user', 'content': 'latest question'},
        ]);
        expect(calls.where((c) => c.method == 'tokenize').length, 2);
      },
    );

    test(
      'oversized critical message rejected instead of string slicing',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => {'tokens': 1800});
        final runtime = LocalRuntime(channel: channel, events: events.stream);
        await expectLater(
          runtime.fitContext(instructions: 'critical', user: 'large'),
          throwsFormatException,
        );
      },
    );
    test(
      'model replacement during load cannot start a stale generation',
      () async {
        var mayGenerate = true;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              if (call.method == 'load') mayGenerate = false;
              return <String, Object?>{};
            });
        final runtime = LocalRuntime(channel: channel, events: events.stream);
        try {
          await expectLater(
            QwenChat(runtime: runtime).ask(
              id: 'stale',
              path: '/synthetic/model',
              query: 'Привет',
              actionSchema: '',
              objectContext: '{}',
              memory: PersonalMemory(),
              history: [],
              onText: (_) => fail('No text from a stale request'),
              isCurrent: () => mayGenerate,
            ),
            throwsA(isA<ModelCancelled>()),
          );
          expect(calls.any((c) => c.method == 'generate'), isFalse);
          expect(calls.any((c) => c.method == 'tokenize'), isFalse);
        } finally {
          await runtime.unload();
        }
      },
    );
  });
}
