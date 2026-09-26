import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/chat/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_intent_router.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_response_configuration.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_route.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_history.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_message.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversational_prompt_builder.dart';
import 'package:slm_ai_chatbot/features/llm/domain/local_llm_service.dart';
import 'package:slm_ai_chatbot/features/rag/domain/document_context_builder.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_prompt_builder.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_search_result.dart';

void main() {
  test(
    'retrieves documents, builds a prompt, and generates an answer',
    () async {
      final ragRepository = _FakeRagRepository([_networkResult]);
      final llmService = _FakeLlmService(
        () => Stream.value('Check Wi-Fi settings.'),
      );

      final contextBuilder = _RecordingContextBuilder();
      final promptBuilder = _RecordingPromptBuilder();
      final useCase = AskQuestionUseCase(
        ragRepository: ragRepository,
        llmService: llmService,
        contextBuilder: contextBuilder,
        promptBuilder: promptBuilder,
        intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
      );

      final result = await useCase(
        'Why can my device not connect to the network?',
      );

      expect(result.status, QuestionAnswerStatus.answered);
      expect(result.answer, 'Check Wi-Fi settings.');
      expect(result.documents.single.id, 'error-e123');
      expect(
        ragRepository.query,
        'Why can my device not connect to the network?',
      );
      expect(contextBuilder.documents.single.id, 'error-e123');
      expect(
        promptBuilder.question,
        'Why can my device not connect to the network?',
      );
      expect(llmService.prompt, 'prompt:context:error-e123');
    },
  );

  test(
    'uses the default retrieval query builder when none is provided',
    () async {
      final ragRepository = _FakeRagRepository([_networkResult]);
      final useCase = AskQuestionUseCase(
        ragRepository: ragRepository,
        llmService: _FakeLlmService(() => Stream.value('Connected.')),
        intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
        retrievalQueryBuilder: null,
      );

      final result = await useCase(
        'Why can my device not connect to the network?',
      );

      expect(result.status, QuestionAnswerStatus.answered);
      expect(
        ragRepository.query,
        'Why can my device not connect to the network?',
      );
    },
  );

  test(
    'streams accumulated answers while preserving call result trimming',
    () async {
      final useCase = AskQuestionUseCase(
        ragRepository: _FakeRagRepository([_networkResult]),
        llmService: _FakeLlmService(
          () => Stream<String>.fromIterable(['Check ', 'Wi-Fi. ']),
        ),
        intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
      );

      Duration? generationDuration;
      var completionCount = 0;
      final streamed = await useCase
          .stream(
            'Why can my device not connect to the network?',
            onGenerationComplete: (duration) {
              generationDuration = duration;
              completionCount++;
            },
          )
          .toList();
      final completed = await useCase(
        'Why can my device not connect to the network?',
      );

      expect(streamed.map((answer) => answer.answer), [
        'Check ',
        'Check Wi-Fi. ',
        'Check Wi-Fi.',
      ]);
      expect(completed.answer, 'Check Wi-Fi.');
      expect(completionCount, 1);
      expect(generationDuration, isNotNull);
      expect(generationDuration, greaterThanOrEqualTo(Duration.zero));
    },
  );

  test('records completion without adding a duplicate answer event', () async {
    final useCase = AskQuestionUseCase(
      ragRepository: _FakeRagRepository([_networkResult]),
      llmService: _FakeLlmService(() => Stream.value('Done.')),
      intentRouter: const _FixedChatIntentRouter(ChatRoute.chat),
    );
    Duration? generationDuration;

    final answers = await useCase
        .stream(
          'Hi',
          onGenerationComplete: (duration) => generationDuration = duration,
        )
        .toList();

    expect(answers.map((answer) => answer.answer), ['Done.']);
    expect(generationDuration, isNotNull);
  });

  test('does not report generation duration for failed generation', () async {
    final useCase = AskQuestionUseCase(
      ragRepository: _FakeRagRepository([_networkResult]),
      llmService: _FakeLlmService(
        () => Stream<String>.error(StateError('Generation failed')),
      ),
      intentRouter: const _FixedChatIntentRouter(ChatRoute.chat),
    );
    var completionCount = 0;

    final answers = await useCase
        .stream('Hi', onGenerationComplete: (_) => completionCount++)
        .toList();

    expect(answers.single.status, QuestionAnswerStatus.modelUnavailable);
    expect(completionCount, 0);
  });

  test('returns a controlled response when retrieval is empty', () async {
    final llmService = _FakeLlmService(Stream<String>.empty);
    final useCase = AskQuestionUseCase(
      ragRepository: _FakeRagRepository(const []),
      llmService: llmService,
      intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
    );

    var completionCount = 0;
    final result = await useCase
        .stream(
          'What is the capital of France?',
          onGenerationComplete: (_) => completionCount++,
        )
        .last;

    expect(result.status, QuestionAnswerStatus.noRelevantKnowledge);
    expect(
      result.answer,
      "I'm an AI assistant designed to help with technical information "
      "available in my knowledge base. I can't answer that question.",
    );
    expect(llmService.prompt, isNull);
    expect(completionCount, 0);
  });

  test(
    'uses conversation context for follow-up retrieval and grounding',
    () async {
      final history = InMemoryConversationHistory();
      history.addAll(const [
        ConversationMessage(
          author: ConversationAuthor.user,
          text: 'What does E123 mean?',
        ),
        ConversationMessage(
          author: ConversationAuthor.assistant,
          text: 'E123 is a network connection error.',
        ),
      ]);
      final ragRepository = _FakeRagRepository([_networkResult]);
      final useCase = AskQuestionUseCase(
        ragRepository: ragRepository,
        llmService: _FakeLlmService(() => Stream.value('Check Wi-Fi.')),
        intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
        conversationHistory: history,
      );

      final result = await useCase('How can I fix it?');

      expect(result.status, QuestionAnswerStatus.answered);
      expect(ragRepository.query, '''
User: What does E123 mean?
Assistant: E123 is a network connection error.
User: How can I fix it?''');
    },
  );

  test(
    'routes chat messages to conversational generation without searching knowledge',
    () async {
      final ragRepository = _FakeRagRepository([_networkResult]);
      final llmService = _FakeLlmService(
        () => Stream<String>.fromIterable(['Hello', ' there. ']),
      );
      final promptBuilder = _RecordingConversationalPromptBuilder();
      final useCase = AskQuestionUseCase(
        ragRepository: ragRepository,
        llmService: llmService,
        intentRouter: const _FixedChatIntentRouter(ChatRoute.chat),
        conversationalPromptBuilder: promptBuilder,
      );

      final streamed = await useCase.stream('Hi there').toList();
      final completed = await useCase('Hi there');

      expect(ragRepository.query, isNull);
      expect(promptBuilder.message, 'Hi there');
      expect(llmService.prompt, 'chat:Hi there');
      expect(streamed.map((answer) => answer.answer), [
        'Hello',
        'Hello there. ',
        'Hello there.',
      ]);
      expect(completed.status, QuestionAnswerStatus.answered);
      expect(completed.documents, isEmpty);
      expect(completed.answer, 'Hello there.');
    },
  );

  test(
    'does not ground unrelated questions in their nearest document',
    () async {
      final ragRepository = _FakeRagRepository([
        const RagSearchResult(
          document: KnowledgeDocument(
            id: 'error-e123',
            title: 'Device cannot connect to network',
            content: 'Check that Wi-Fi is enabled.',
            metadata: {'type': 'error', 'code': 'E123'},
          ),
          similarity: 0.99,
        ),
      ]);
      final llmService = _FakeLlmService(Stream<String>.empty);
      final useCase = AskQuestionUseCase(
        ragRepository: ragRepository,
        llmService: llmService,
        intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
      );

      for (final question in [
        'What is the capital of France?',
        'Tell me a joke.',
        'What is the weather today?',
        'Write me a poem.',
      ]) {
        final result = await useCase(question);

        expect(result.status, QuestionAnswerStatus.noRelevantKnowledge);
        expect(result.documents, isEmpty);
      }
      expect(ragRepository.threshold, 0);
      expect(llmService.prompt, isNull);
    },
  );

  test('uses the configured unsupported-question message', () async {
    final useCase = AskQuestionUseCase(
      ragRepository: _FakeRagRepository(const []),
      llmService: _FakeLlmService(Stream<String>.empty),
      intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
      responseConfiguration: const ChatResponseConfiguration(
        unsupportedQuestionMessage: 'Custom fallback',
      ),
    );

    final result = await useCase('What is the capital of France?');

    expect(result.answer, 'Custom fallback');
  });

  test('returns a controlled response when retrieval fails', () async {
    final useCase = AskQuestionUseCase(
      ragRepository: _ThrowingRagRepository(),
      llmService: _FakeLlmService(Stream<String>.empty),
      intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
    );

    final result = await useCase(
      'Why can my device not connect to the network?',
    );

    expect(result.status, QuestionAnswerStatus.retrievalFailure);
  });

  test('returns a controlled response when local generation fails', () async {
    final useCase = AskQuestionUseCase(
      ragRepository: _FakeRagRepository([_networkResult]),
      llmService: _FakeLlmService(
        () => Stream<String>.error(Exception('generation failed')),
      ),
      intentRouter: const _FixedChatIntentRouter(ChatRoute.chat),
    );

    final result = await useCase('Hi there');

    expect(result.status, QuestionAnswerStatus.generationFailure);
    expect(result.documents, isEmpty);
  });

  test(
    'returns a controlled response when the local model is unavailable',
    () async {
      final useCase = AskQuestionUseCase(
        ragRepository: _FakeRagRepository([_networkResult]),
        llmService: _FakeLlmService(
          () => Stream<String>.error(StateError('No active model')),
        ),
        intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
      );

      final result = await useCase(
        'Why can my device not connect to the network?',
      );

      expect(result.status, QuestionAnswerStatus.modelUnavailable);
      expect(
        result.answer,
        'Local AI model is not installed or could not be loaded.',
      );
    },
  );

  test('uses stored history for chat without searching knowledge', () async {
    final history = InMemoryConversationHistory();
    history.addAll(const [
      ConversationMessage(author: ConversationAuthor.user, text: 'Hello'),
      ConversationMessage(
        author: ConversationAuthor.assistant,
        text: 'Hi there.',
      ),
    ]);
    final ragRepository = _FakeRagRepository([_networkResult]);
    final llmService = _FakeLlmService(() => Stream.value('You too.'));
    final router = _HistoryRouter(ChatRoute.chat);
    final useCase = AskQuestionUseCase(
      ragRepository: ragRepository,
      llmService: llmService,
      intentRouter: router,
      conversationHistory: history,
    );

    await useCase('How are you?');

    expect(ragRepository.query, isNull);
    expect(router.history.map((message) => message.text), [
      'Hello',
      'Hi there.',
    ]);
    expect(
      llmService.prompt,
      allOf(contains('Hello'), contains('How are you?')),
    );
    expect(history.messages.map((message) => message.text), [
      'Hello',
      'Hi there.',
      'How are you?',
      'You too.',
    ]);
  });

  test(
    'uses history for relevant knowledge and preserves empty history',
    () async {
      final history = InMemoryConversationHistory();
      final llmService = _FakeLlmService(() => Stream.value('Check Wi-Fi.'));
      final router = _HistoryRouter(ChatRoute.knowledge);
      final useCase = AskQuestionUseCase(
        ragRepository: _FakeRagRepository([_networkResult]),
        llmService: llmService,
        intentRouter: router,
        conversationHistory: history,
      );

      final result = await useCase('Why can my device not connect to network?');

      expect(result.status, QuestionAnswerStatus.answered);
      expect(router.history, isEmpty);
      expect(
        llmService.prompt,
        allOf(contains('<knowledge>'), contains('<conversation_history>')),
      );
      expect(history.messages, hasLength(2));
      useCase.clearHistory();
      expect(history.messages, isEmpty);
    },
  );

  test(
    'regenerates the selected CHAT turn with only preceding history',
    () async {
      final history = InMemoryConversationHistory(maxMessages: 8);
      final router = _HistoryRouter(ChatRoute.chat);
      var answerNumber = 0;
      final llm = _FakeLlmService(
        () => Stream.value('Answer ${++answerNumber}'),
      );
      final useCase = AskQuestionUseCase(
        ragRepository: _FakeRagRepository([_networkResult]),
        llmService: llm,
        intentRouter: router,
        conversationHistory: history,
      );
      await useCase.stream('First', turnId: 'one').last;
      await useCase.stream('Repeated', turnId: 'two').last;
      await useCase.stream('Repeated', turnId: 'three').last;

      final updated = await useCase
          .stream('Repeated', turnId: 'two', regenerate: true)
          .last;
      expect(updated.answer, 'Answer 4');
      expect(router.history.map((message) => message.text), [
        'First',
        'Answer 1',
      ]);
      expect(llm.prompt, contains('Answer 1'));
      expect(llm.prompt, isNot(contains('Answer 2')));
      expect(llm.prompt, isNot(contains('Answer 3')));
      expect(history.messages.map((message) => message.text), [
        'First',
        'Answer 1',
        'Repeated',
        'Answer 4',
        'Repeated',
        'Answer 3',
      ]);
    },
  );

  test(
    'regenerates KNOWLEDGE using fresh retrieval and replaces history',
    () async {
      final history = InMemoryConversationHistory();
      final router = _HistoryRouter(ChatRoute.knowledge);
      final repository = _FakeRagRepository([_networkResult]);
      var answerNumber = 0;
      final useCase = AskQuestionUseCase(
        ragRepository: repository,
        llmService: _FakeLlmService(
          () => Stream.value('Answer ${++answerNumber}'),
        ),
        intentRouter: router,
        conversationHistory: history,
      );
      const question = 'How do I fix E123?';
      await useCase.stream(question, turnId: 'answer').last;
      repository.results = const [
        RagSearchResult(
          document: KnowledgeDocument(
            id: 'new-guide',
            title: 'E123 network guide',
            content: 'Restart the network connection.',
            metadata: {'code': 'E123'},
          ),
          similarity: 0.99,
        ),
      ];

      final updated = await useCase
          .stream(
            question,
            turnId: 'answer',
            regenerate: true,
            isLatestTurn: true,
          )
          .last;
      expect(router.history, isEmpty);
      expect(repository.query, question);
      expect(updated.documents.single.id, 'new-guide');
      expect(updated.answer, 'Answer 2');
      expect(history.messages.map((message) => message.text), [
        question,
        'Answer 2',
      ]);
    },
  );

  test(
    'failed regeneration retains history and successful fallback removes it',
    () async {
      final history = InMemoryConversationHistory();
      final repository = _FakeRagRepository([_networkResult]);
      final useCase = AskQuestionUseCase(
        ragRepository: repository,
        llmService: _FakeLlmService(() => Stream.value('Original')),
        intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
        conversationHistory: history,
      );
      const question = 'How do I fix E123?';
      await useCase.stream(question, turnId: 'answer').last;
      repository.results = const [];
      final fallback = await useCase
          .stream(
            question,
            turnId: 'answer',
            regenerate: true,
            isLatestTurn: true,
          )
          .last;
      expect(fallback.status, QuestionAnswerStatus.noRelevantKnowledge);
      expect(history.messages, isEmpty);

      repository.results = [_networkResult];
      await useCase.stream(question, turnId: 'answer').last;
      final failedUseCase = AskQuestionUseCase(
        ragRepository: repository,
        llmService: _FakeLlmService(
          () => Stream<String>.error(StateError('Unavailable')),
        ),
        intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
        conversationHistory: history,
      );
      final failure = await failedUseCase
          .stream(
            question,
            turnId: 'answer',
            regenerate: true,
            isLatestTurn: true,
          )
          .last;
      expect(failure.status, QuestionAnswerStatus.modelUnavailable);
      expect(history.messages.map((message) => message.text), [
        question,
        'Original',
      ]);
    },
  );

  test(
    'successful regeneration after an unstored fallback adds one turn',
    () async {
      final history = InMemoryConversationHistory();
      final repository = _FakeRagRepository(const []);
      final useCase = AskQuestionUseCase(
        ragRepository: repository,
        llmService: _FakeLlmService(() => Stream.value('Now grounded')),
        intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
        conversationHistory: history,
      );
      const question = 'How do I fix E123?';
      final fallback = await useCase.stream(question, turnId: 'answer').last;
      expect(fallback.status, QuestionAnswerStatus.noRelevantKnowledge);
      expect(history.messages, isEmpty);
      repository.results = [_networkResult];

      final updated = await useCase
          .stream(
            question,
            turnId: 'answer',
            regenerate: true,
            isLatestTurn: true,
          )
          .last;
      expect(updated.status, QuestionAnswerStatus.answered);
      expect(history.messages.map((message) => message.text), [
        question,
        'Now grounded',
      ]);
    },
  );

  test(
    'aged-out turn does not pollute recent conversation on regeneration',
    () async {
      final history = InMemoryConversationHistory(maxMessages: 2);
      final router = _HistoryRouter(ChatRoute.chat);
      var number = 0;
      final useCase = AskQuestionUseCase(
        ragRepository: _FakeRagRepository([_networkResult]),
        llmService: _FakeLlmService(() => Stream.value('Answer ${++number}')),
        intentRouter: router,
        conversationHistory: history,
      );
      await useCase.stream('Old', turnId: 'old').last;
      await useCase.stream('New', turnId: 'new').last;
      final updated = await useCase
          .stream('Old', turnId: 'old', regenerate: true)
          .last;
      expect(updated.answer, 'Answer 3');
      expect(router.history, isEmpty);
      expect(history.messages.map((message) => message.text), [
        'New',
        'Answer 2',
      ]);
    },
  );
}

const _networkResult = RagSearchResult(
  document: KnowledgeDocument(
    id: 'error-e123',
    title: 'Device cannot connect to network',
    content: 'Check that Wi-Fi is enabled.',
    metadata: {'type': 'error', 'code': 'E123'},
  ),
  similarity: 0.95,
);

class _FixedChatIntentRouter implements ChatIntentRouter {
  const _FixedChatIntentRouter(this.routeValue);

  final ChatRoute routeValue;

  @override
  Future<ChatRoute> route(String message) async => routeValue;
}

class _HistoryRouter implements HistoryAwareChatIntentRouter {
  _HistoryRouter(this.routeValue);

  final ChatRoute routeValue;
  List<ConversationMessage> history = const [];

  @override
  Future<ChatRoute> route(String message) async => routeValue;

  @override
  Future<ChatRoute> routeWithHistory(
    String message, {
    List<ConversationMessage> history = const [],
  }) async {
    this.history = history;
    return routeValue;
  }
}

class _FakeRagRepository implements RagRepository {
  _FakeRagRepository(this.results);

  List<RagSearchResult> results;
  String? query;
  double? threshold;

  @override
  Future<void> indexDocuments(Iterable<RagDocument> documents) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<List<RagSearchResult>> search({
    required String query,
    int topK = 1,
    double threshold = 0.0,
  }) async {
    this.query = query;
    this.threshold = threshold;
    return results;
  }
}

class _ThrowingRagRepository implements RagRepository {
  @override
  Future<void> indexDocuments(Iterable<RagDocument> documents) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<List<RagSearchResult>> search({
    required String query,
    int topK = 1,
    double threshold = 0.0,
  }) {
    throw StateError('Search failed');
  }
}

class _FakeLlmService implements LocalLlmService {
  _FakeLlmService(this._responses);

  final Stream<String> Function() _responses;
  String? prompt;

  @override
  Future<void> dispose() async {}

  @override
  Stream<String> generate(String prompt) {
    this.prompt = prompt;
    return _responses();
  }

  @override
  Future<void> stop() async {}
}

class _RecordingContextBuilder extends DocumentContextBuilder {
  List<KnowledgeDocument> documents = const [];

  @override
  String build(Iterable<KnowledgeDocument> documents) {
    this.documents = documents.toList(growable: false);
    return 'context:${this.documents.single.id}';
  }
}

class _RecordingPromptBuilder extends RagPromptBuilder {
  String? question;

  @override
  String build({
    required String question,
    required String context,
    List<ConversationMessage> history = const [],
  }) {
    this.question = question;
    return 'prompt:$context';
  }
}

class _RecordingConversationalPromptBuilder
    extends ConversationalPromptBuilder {
  String? message;

  @override
  String build(String message, {List<ConversationMessage> history = const []}) {
    this.message = message;
    return 'chat:$message';
  }
}
