import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/core/profiling/ai_latency_profile.dart';
import 'package:slm_ai_chatbot/features/chat/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_history.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_message.dart';
import 'package:slm_ai_chatbot/features/llm/data/local_llm_service_impl.dart';
import 'package:slm_ai_chatbot/features/llm/domain/local_llm_service.dart';
import 'package:slm_ai_chatbot/features/rag/data/flutter_gemma_rag_sqlite_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_search_result.dart';

void main() {
  test('fallback records retrieval, prompt, history and generation', () async {
    final logs = <String>[];
    final profile = AiLatencyProfile(requestNumber: 1, log: logs.add);
    final history = InMemoryConversationHistory()
      ..addAll(const [
        ConversationMessage(
          author: ConversationAuthor.user,
          text: 'Secret prior',
        ),
        ConversationMessage(
          author: ConversationAuthor.assistant,
          text: 'Previous',
        ),
      ]);
    final rag = _Rag();
    final llm = _Llm(() => Stream.fromIterable(['Hello', ' there ']));
    final useCase = AskQuestionUseCase(
      ragRepository: rag,
      llmService: llm,
      conversationHistory: history,
    );
    const question = 'Private question xyz';
    final answers = await AiLatencyProfile.run(
      profile,
      () async => useCase.stream(question).toList(),
    );
    profile.complete(answers.last.status.name);
    profile.complete('ignored');

    expect(answers.map((answer) => answer.answer), [
      'Hello',
      'Hello there ',
      'Hello there',
    ]);
    expect(answers.last.documents, isEmpty);
    expect(rag.searches, 1);
    expect(profile.historyMessageCount, 2);
    expect(profile.historyCharacters, greaterThan(0));
    expect(profile.userQueryCharacters, question.length);
    expect(profile.chatPromptCharacters, llm.prompt!.length);
    expect(profile.ragPromptCharacters, isNull);
    expect(profile.elapsedAt(AiProfileEvent.promptBuildEnd), isNotNull);
    expect(profile.elapsedAt(AiProfileEvent.finalLlmStart), isNotNull);
    expect(profile.elapsedAt(AiProfileEvent.finalLlmEnd), isNotNull);
    expect(profile.elapsedAt(AiProfileEvent.searchStart), isNotNull);
    expect(profile.elapsedAt(AiProfileEvent.searchEnd), isNotNull);
    expect(
      logs.where((line) => line.contains('Request complete')),
      hasLength(1),
    );
    expect(logs.join('\n'), contains('Request complete: status=answered'));
    expect(logs.join('\n'), contains('Results: retrieved=0, grounded=0'));
    expect(logs.join('\n'), contains('Prompt characters: fallback='));
    expect(logs.join('\n'), isNot(contains('Router:')));
    expect(logs.join('\n'), contains('Final native metrics: Not available'));
    expect(logs.join('\n'), isNot(contains(question)));
    expect(logs.join('\n'), isNot(contains('Secret prior')));
    expect(logs.join('\n'), isNot(contains('Hello there')));
  });

  test(
    'grounded answer profiles search and decode without changing response',
    () async {
      final logs = <String>[];
      final profile = AiLatencyProfile(requestNumber: 2, log: logs.add);
      final runtime = _Runtime();
      final rag = FlutterGemmaRagSqliteRepository(
        databasePathProvider: () async => 'local.db',
        runtime: runtime,
      );
      final llm = _Llm(() => Stream.value('Check Wi-Fi.'));
      final useCase = AskQuestionUseCase(ragRepository: rag, llmService: llm);
      const question = 'How do I fix E123 network?';
      final answers = await AiLatencyProfile.run(
        profile,
        () async => useCase.stream(question).toList(),
      );
      profile.complete(answers.last.status.name);

      expect(answers.last.status, QuestionAnswerStatus.answered);
      expect(answers.last.answer, 'Check Wi-Fi.');
      expect(answers.last.documents.single.id, 'e123');
      expect(runtime.query, question);
      expect(runtime.topK, 3);
      expect(llm.calls, 1);
      expect(profile.retrievedCount, 1);
      expect(profile.groundedCount, 1);
      expect(profile.retrievedContextCharacters, greaterThan(0));
      expect(profile.ragPromptCharacters, llm.prompt!.length);
      expect(profile.chatPromptCharacters, isNull);
      for (final event in [
        AiProfileEvent.retrievalQueryStart,
        AiProfileEvent.retrievalQueryEnd,
        AiProfileEvent.searchStart,
        AiProfileEvent.searchEnd,
        AiProfileEvent.embeddingAndVectorSearchStart,
        AiProfileEvent.embeddingAndVectorSearchEnd,
        AiProfileEvent.metadataDecodeStart,
        AiProfileEvent.metadataDecodeEnd,
        AiProfileEvent.groundingStart,
        AiProfileEvent.groundingEnd,
        AiProfileEvent.contextBuildStart,
        AiProfileEvent.contextBuildEnd,
        AiProfileEvent.promptBuildStart,
        AiProfileEvent.promptBuildEnd,
        AiProfileEvent.finalLlmStart,
        AiProfileEvent.finalLlmEnd,
      ]) {
        expect(profile.elapsedAt(event), isNotNull, reason: '$event');
      }
      expect(logs.join('\n'), contains('Results: retrieved=1, grounded=1'));
      expect(logs.join('\n'), contains('Request complete: status=answered'));
      expect(logs.join('\n'), isNot(contains(question)));
      expect(logs.join('\n'), isNot(contains('Check Wi-Fi.')));
    },
  );

  test(
    'empty retrieval generates once but retrieval errors stop generation',
    () async {
      for (final failing in [false, true]) {
        final profile = AiLatencyProfile(requestNumber: 3, log: (_) {});
        final rag = _Rag(failing: failing);
        final llm = _Llm(() => Stream.value('Generated fallback'));
        final useCase = AskQuestionUseCase(ragRepository: rag, llmService: llm);
        final answers = await AiLatencyProfile.run(
          profile,
          () async => useCase.stream('Unrelated question').toList(),
        );
        expect(answers, hasLength(1));
        expect(
          answers.single.status,
          failing
              ? QuestionAnswerStatus.retrievalFailure
              : QuestionAnswerStatus.answered,
        );
        expect(profile.retrievedCount, failing ? isNull : 0);
        expect(profile.groundedCount, failing ? isNull : 0);
        expect(profile.elapsedAt(AiProfileEvent.searchEnd), isNotNull);
        expect(
          profile.elapsedAt(AiProfileEvent.finalLlmStart),
          failing ? isNull : isNotNull,
        );
        expect(llm.calls, failing ? 0 : 1);
        expect(
          llm.prompt,
          failing ? isNull : contains('respond with exactly:'),
        );
      }
    },
  );

  test(
    'generation errors preserve controlled status and mark LLM end',
    () async {
      for (final error in [
        StateError('private failure'),
        Exception('private failure'),
      ]) {
        final profile = AiLatencyProfile(requestNumber: 4, log: (_) {});
        final useCase = AskQuestionUseCase(
          ragRepository: _Rag(),
          llmService: _Llm(() => Stream.error(error)),
        );
        final answers = await AiLatencyProfile.run(
          profile,
          () async => useCase.stream('Hi').toList(),
        );
        expect(
          answers.single.status,
          error is StateError
              ? QuestionAnswerStatus.modelUnavailable
              : QuestionAnswerStatus.generationFailure,
        );
        expect(profile.elapsedAt(AiProfileEvent.finalLlmStart), isNotNull);
        expect(profile.elapsedAt(AiProfileEvent.finalLlmEnd), isNotNull);
      }
    },
  );

  test(
    'absent zone and null profile do not mark an unrelated profile',
    () async {
      final profile = AiLatencyProfile(requestNumber: 6, log: (_) {});
      final useCase = AskQuestionUseCase(
        ragRepository: _Rag(),
        llmService: _Llm(() => Stream.value('Hello')),
      );
      expect(AiLatencyProfile.current, isNull);
      await AiLatencyProfile.run(
        null,
        () async => useCase.stream('Hi').toList(),
      );
      await useCase.stream('Hi again').toList();
      expect(AiLatencyProfile.current, isNull);
      expect(profile.elapsedAt(AiProfileEvent.retrievalQueryStart), isNull);
      expect(profile.chatPromptCharacters, isNull);
    },
  );

  test('direct LiteRT session requests a non-thinking Qwen response', () async {
    final session = _Session();
    final service = LocalLlmServiceImpl(
      modelProvider: () async => _Model(session),
      releaseModel: () async {},
    );
    final logs = <String>[];
    final profile = AiLatencyProfile(requestNumber: 7, log: logs.add);
    final chunks = await AiLatencyProfile.run(profile, () async {
      profile.generationPhase = AiGenerationPhase.finalAnswer;
      return service.generate('Sensitive prompt').toList();
    });
    profile.complete('answered');
    expect(chunks.join(), 'Generated text');
    expect(session.query, 'Sensitive prompt /no_think');
    expect(session.closed, isTrue);
    expect(profile.elapsedAt(AiProfileEvent.firstRawChunk), isNotNull);
    expect(profile.elapsedAt(AiProfileEvent.firstParsedChunk), isNotNull);
    expect(logs.join('\n'), contains('Final native metrics: Not available'));
    expect(logs.join('\n'), isNot(contains('Sensitive prompt')));
  });

  test('reads native counts and TTFT before closing the session', () async {
    final session = _Session(
      metrics: SessionMetrics(
        inputTokens: 120,
        outputTokens: 14,
        totalTokens: 134,
        timeToFirstTokenMs: 36.5,
        tokensPerSecond: 12.75,
        initTimeMs: 4.0,
      ),
    );
    final service = LocalLlmServiceImpl(
      modelProvider: () async => _Model(session),
      releaseModel: () async {},
    );
    final logs = <String>[];
    final profile = AiLatencyProfile(requestNumber: 9, log: logs.add);
    final answer = await AiLatencyProfile.run(profile, () async {
      profile.generationPhase = AiGenerationPhase.finalAnswer;
      return service.generate('Sensitive prompt').join();
    });
    profile.complete('answered');

    expect(answer, 'Generated text');
    expect(session.metricsReadBeforeClose, isTrue);
    expect(session.closed, isTrue);
    expect(logs.join('\n'), contains('input=120, output=14, TTFT=36.50ms'));
    expect(logs.join('\n'), contains('tokens/sec=12.75, init=4.00ms'));
    expect(logs.join('\n'), isNot(contains('Sensitive prompt')));
  });

  test('keeps raw and parsed first-chunk times distinct', () async {
    final raw = StreamController<String>();
    final session = _Session(output: raw.stream);
    final service = LocalLlmServiceImpl(
      modelProvider: () async => _Model(session),
      releaseModel: () async {},
    );
    final profile = AiLatencyProfile(requestNumber: 10, log: (_) {});
    final answer = AiLatencyProfile.run(profile, () async {
      profile.generationPhase = AiGenerationPhase.finalAnswer;
      return service.generate('Prompt').join();
    });
    raw.add('Plain ');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(profile.elapsedAt(AiProfileEvent.firstRawChunk), isNotNull);
    expect(profile.elapsedAt(AiProfileEvent.firstParsedChunk), isNull);
    await raw.close();
    expect(await answer, 'Plain ');
    expect(profile.elapsedAt(AiProfileEvent.firstParsedChunk), isNotNull);
  });

  test('first rendered text is recorded once after presentation', () {
    final logs = <String>[];
    final profile = AiLatencyProfile(requestNumber: 8, log: logs.add);
    profile.recordFirstRenderedText();
    expect(profile.elapsedAt(AiProfileEvent.firstRenderedText), isNull);
    profile.mark(AiProfileEvent.firstPresentationText);
    expect(profile.isFirstRenderedTextPending, isTrue);
    profile.complete('answered');
    expect(
      logs.join('\n'),
      contains('first visible assistant text (post-frame): Not available'),
    );
    profile.recordFirstRenderedText();
    profile.recordFirstRenderedText();
    expect(profile.isFirstRenderedTextPending, isFalse);
    expect(profile.elapsedAt(AiProfileEvent.firstRenderedText), isNotNull);
    expect(
      logs.where(
        (line) => line.contains('First visible assistant text (post-frame):'),
      ),
      hasLength(1),
    );
  });
}

class _Llm implements LocalLlmService {
  _Llm(this.respond);
  final Stream<String> Function() respond;
  String? prompt;
  int calls = 0;
  @override
  Stream<String> generate(String prompt) {
    this.prompt = prompt;
    calls++;
    return respond();
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _Rag implements RagRepository {
  _Rag({this.failing = false});
  final bool failing;
  int searches = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> indexDocuments(Iterable<RagDocument> documents) async {}
  @override
  Future<List<RagSearchResult>> search({
    required String query,
    String? exactMatchQuery,
    int topK = 1,
    double threshold = 0,
  }) async {
    searches++;
    if (failing) throw StateError('private search failure');
    return [];
  }
}

class _Runtime extends FlutterGemmaRagRuntime {
  String? query;
  int? topK;
  @override
  Future<void> initializeVectorStore(String databasePath) async {}
  @override
  Future<List<FlutterGemmaRagRuntimeResult>> searchSimilar({
    required String query,
    required int topK,
    required double threshold,
  }) async {
    this.query = query;
    this.topK = topK;
    return const [
      FlutterGemmaRagRuntimeResult(
        id: 'e123',
        content: 'E123 network error',
        similarity: 0.98,
        metadata:
            '{"_knowledgeDocument":{"title":"E123 network error","content":"Check Wi-Fi.","metadata":{"code":"E123"}}}',
      ),
    ];
  }
}

class _Model implements InferenceModel {
  _Model(this.fakeSession);
  final InferenceModelSession fakeSession;
  @override
  PreferredBackend? get activeBackend => null;
  @override
  Future<InferenceModelSession> createSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality,
    bool? enableAudioModality,
    String? systemInstruction,
    bool enableThinking = false,
    List<Tool> tools = const [],
  }) async => fakeSession;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements InferenceModelSession {
  _Session({this.metrics, this.output});

  final SessionMetrics? metrics;
  final Stream<String>? output;
  String? query;
  bool closed = false;
  bool metricsReadBeforeClose = false;
  @override
  Future<void> addQueryChunk(Message message) async => query = message.text;
  @override
  Stream<String> getResponseAsync() => output ?? Stream.value('Generated text');
  @override
  SessionMetrics getSessionMetrics() {
    metricsReadBeforeClose = !closed;
    if (closed) throw StateError('The session was closed before metrics');
    return metrics ?? (throw UnsupportedError('No metrics'));
  }

  @override
  Future<void> close() async => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
