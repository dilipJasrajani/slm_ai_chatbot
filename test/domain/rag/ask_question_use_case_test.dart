import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/domain/chat/chat_intent_router.dart';
import 'package:slm_ai_chatbot/domain/chat/chat_route.dart';
import 'package:slm_ai_chatbot/domain/chat/conversational_prompt_builder.dart';
import 'package:slm_ai_chatbot/domain/llm/local_llm_service.dart';
import 'package:slm_ai_chatbot/domain/rag/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/domain/rag/chat_response_configuration.dart';
import 'package:slm_ai_chatbot/domain/rag/document_context_builder.dart';
import 'package:slm_ai_chatbot/domain/rag/knowledge_document.dart';
import 'package:slm_ai_chatbot/domain/rag/rag_document.dart';
import 'package:slm_ai_chatbot/domain/rag/rag_prompt_builder.dart';
import 'package:slm_ai_chatbot/domain/rag/rag_repository.dart';
import 'package:slm_ai_chatbot/domain/rag/rag_search_result.dart';

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
    'streams accumulated answers while preserving call result trimming',
    () async {
      final useCase = AskQuestionUseCase(
        ragRepository: _FakeRagRepository([_networkResult]),
        llmService: _FakeLlmService(
          () => Stream<String>.fromIterable(['Check ', 'Wi-Fi. ']),
        ),
        intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
      );

      final streamed = await useCase
          .stream('Why can my device not connect to the network?')
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
    },
  );

  test('returns a controlled response when retrieval is empty', () async {
    final llmService = _FakeLlmService(Stream<String>.empty);
    final useCase = AskQuestionUseCase(
      ragRepository: _FakeRagRepository(const []),
      llmService: llmService,
      intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
    );

    final result = await useCase('What is the capital of France?');

    expect(result.status, QuestionAnswerStatus.noRelevantKnowledge);
    expect(
      result.answer,
      "I'm an AI assistant designed to help with technical information "
      "available in my knowledge base. I can't answer that question.",
    );
    expect(llmService.prompt, isNull);
  });

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

class _FakeRagRepository implements RagRepository {
  _FakeRagRepository(this.results);

  final List<RagSearchResult> results;
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
  String build({required String question, required String context}) {
    this.question = question;
    return 'prompt:$context';
  }
}

class _RecordingConversationalPromptBuilder
    extends ConversationalPromptBuilder {
  String? message;

  @override
  String build(String message) {
    this.message = message;
    return 'chat:$message';
  }
}
