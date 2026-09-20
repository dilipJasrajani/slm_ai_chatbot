import '../chat/chat_intent_router.dart';
import '../chat/chat_route.dart';
import '../chat/conversational_prompt_builder.dart';
import '../chat/deterministic_chat_intent_router.dart';
import 'chat_response_configuration.dart';
import '../llm/local_llm_service.dart';
import 'document_context_builder.dart';
import 'knowledge_document.dart';
import 'rag_prompt_builder.dart';
import 'rag_repository.dart';
import 'rag_search_result.dart';
import 'retrieved_knowledge_relevance.dart';

enum QuestionAnswerStatus {
  answered,
  noRelevantKnowledge,
  retrievalFailure,
  modelUnavailable,
  generationFailure,
}

class QuestionAnswer {
  const QuestionAnswer({
    required this.status,
    required this.answer,
    this.documents = const [],
  });

  final QuestionAnswerStatus status;
  final String answer;
  final List<KnowledgeDocument> documents;
}

class AskQuestionUseCase {
  AskQuestionUseCase({
    required RagRepository ragRepository,
    required LocalLlmService llmService,
    DocumentContextBuilder contextBuilder = const DocumentContextBuilder(),
    RagPromptBuilder promptBuilder = const RagPromptBuilder(),
    ChatIntentRouter intentRouter = const DeterministicChatIntentRouter(),
    ConversationalPromptBuilder conversationalPromptBuilder =
        const ConversationalPromptBuilder(),
    RetrievedKnowledgeRelevance relevance = const RetrievedKnowledgeRelevance(),
    ChatResponseConfiguration responseConfiguration =
        const ChatResponseConfiguration(),
  }) : _ragRepository = ragRepository,
       _llmService = llmService,
       _contextBuilder = contextBuilder,
       _promptBuilder = promptBuilder,
       _intentRouter = intentRouter,
       _conversationalPromptBuilder = conversationalPromptBuilder,
       _relevance = relevance,
       _responseConfiguration = responseConfiguration;

  final RagRepository _ragRepository;
  final LocalLlmService _llmService;
  final DocumentContextBuilder _contextBuilder;
  final RagPromptBuilder _promptBuilder;
  final ChatIntentRouter _intentRouter;
  final ConversationalPromptBuilder _conversationalPromptBuilder;
  final RetrievedKnowledgeRelevance _relevance;
  final ChatResponseConfiguration _responseConfiguration;

  Future<void> cancel() => _llmService.stop();

  Future<QuestionAnswer> call(String question) async {
    return stream(question).last;
  }

  /// Emits the complete answer accumulated so far as local generation streams.
  ///
  /// Retrieval and generation failures are emitted as a single controlled
  /// answer, matching [call].
  Stream<QuestionAnswer> stream(String question) async* {
    final route = await _routeQuestion(question);
    if (route == ChatRoute.chat) {
      final prompt = _conversationalPromptBuilder.build(question);
      yield* _generateResponse(prompt, const []);
      return;
    }

    final searchResults = await _retrieveKnowledge(question);
    if (searchResults == null) {
      yield const QuestionAnswer(
        status: QuestionAnswerStatus.retrievalFailure,
        answer: 'Unable to search the local knowledge base.',
      );
      return;
    }
    final documents = _relevance.relevantDocuments(
      question: question,
      results: searchResults,
    );
    if (documents.isEmpty) {
      yield QuestionAnswer(
        status: QuestionAnswerStatus.noRelevantKnowledge,
        answer: _responseConfiguration.unsupportedQuestionMessage,
      );
      return;
    }

    final prompt = _promptBuilder.build(
      question: question,
      context: _contextBuilder.build(documents),
    );
    yield* _generateResponse(prompt, documents);
  }

  Future<ChatRoute> _routeQuestion(String question) async {
    try {
      return await _intentRouter.route(question);
    } catch (_) {
      return ChatRoute.knowledge;
    }
  }

  Stream<QuestionAnswer> _generateResponse(
    String prompt,
    List<KnowledgeDocument> documents,
  ) async* {
    try {
      final response = StringBuffer();
      await for (final chunk in _llmService.generate(prompt)) {
        response.write(chunk);
        yield QuestionAnswer(
          status: QuestionAnswerStatus.answered,
          answer: response.toString(),
          documents: documents,
        );
      }
      final answer = response.toString().trim();
      if (answer.isEmpty) {
        yield QuestionAnswer(
          status: QuestionAnswerStatus.generationFailure,
          answer: 'The local AI model did not generate an answer.',
          documents: documents,
        );
        return;
      }
      if (answer != response.toString()) {
        yield QuestionAnswer(
          status: QuestionAnswerStatus.answered,
          answer: answer,
          documents: documents,
        );
      }
    } on StateError {
      yield QuestionAnswer(
        status: QuestionAnswerStatus.modelUnavailable,
        answer: 'Local AI model is not installed or could not be loaded.',
        documents: documents,
      );
    } catch (_) {
      yield QuestionAnswer(
        status: QuestionAnswerStatus.generationFailure,
        answer: 'Unable to generate an answer with the local AI model.',
        documents: documents,
      );
    }
  }

  Future<List<RagSearchResult>?> _retrieveKnowledge(String question) async {
    try {
      return await _ragRepository.search(query: question, topK: 3);
    } catch (_) {
      return null;
    }
  }
}
