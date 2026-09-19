import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/domain/llm/local_llm_service.dart';
import 'package:slm_ai_chatbot/domain/rag/ask_question_use_case.dart';
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
      final llmService = _FakeLlmService(Stream.value('Check Wi-Fi settings.'));
      final contextBuilder = _RecordingContextBuilder();
      final promptBuilder = _RecordingPromptBuilder();
      final useCase = AskQuestionUseCase(
        ragRepository: ragRepository,
        llmService: llmService,
        contextBuilder: contextBuilder,
        promptBuilder: promptBuilder,
      );

      final result = await useCase('What should I check?');

      expect(result.status, QuestionAnswerStatus.answered);
      expect(result.answer, 'Check Wi-Fi settings.');
      expect(result.documents.single.id, 'error-e123');
      expect(ragRepository.query, 'What should I check?');
      expect(contextBuilder.documents.single.id, 'error-e123');
      expect(promptBuilder.question, 'What should I check?');
      expect(llmService.prompt, 'prompt:context:error-e123');
    },
  );

  test('returns a controlled response when retrieval is empty', () async {
    final llmService = _FakeLlmService(const Stream.empty());
    final useCase = AskQuestionUseCase(
      ragRepository: _FakeRagRepository(const []),
      llmService: llmService,
    );

    final result = await useCase('What is the capital of France?');

    expect(result.status, QuestionAnswerStatus.noRelevantKnowledge);
    expect(result.answer, AskQuestionUseCase.noRelevantKnowledgeAnswer);
    expect(llmService.prompt, isNull);
  });

  test('returns a controlled response when retrieval fails', () async {
    final useCase = AskQuestionUseCase(
      ragRepository: _ThrowingRagRepository(),
      llmService: _FakeLlmService(const Stream.empty()),
    );

    final result = await useCase('What should I check?');

    expect(result.status, QuestionAnswerStatus.retrievalFailure);
  });

  test('returns a controlled response when local generation fails', () async {
    final useCase = AskQuestionUseCase(
      ragRepository: _FakeRagRepository([_networkResult]),
      llmService: _FakeLlmService(Stream.error(Exception('generation failed'))),
    );

    final result = await useCase('What should I check?');

    expect(result.status, QuestionAnswerStatus.generationFailure);
    expect(result.documents.single.id, 'error-e123');
  });

  test(
    'returns a controlled response when the local model is unavailable',
    () async {
      final useCase = AskQuestionUseCase(
        ragRepository: _FakeRagRepository([_networkResult]),
        llmService: _FakeLlmService(
          Stream.error(StateError('No active model')),
        ),
      );

      final result = await useCase('What should I check?');

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

class _FakeRagRepository implements RagRepository {
  _FakeRagRepository(this.results);

  final List<RagSearchResult> results;
  String? query;

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
  _FakeLlmService(this.response);

  final Stream<String> response;
  String? prompt;

  @override
  Future<void> dispose() async {}

  @override
  Stream<String> generate(String prompt) {
    this.prompt = prompt;
    return response;
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
