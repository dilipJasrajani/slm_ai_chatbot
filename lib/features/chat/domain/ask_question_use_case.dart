import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'package:slm_ai_chatbot/core/profiling/ai_latency_profile.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_intent_router.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_response_configuration.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_route.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_history.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_message.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversational_prompt_builder.dart';
import 'package:slm_ai_chatbot/features/chat/domain/deterministic_chat_intent_router.dart';
import 'package:slm_ai_chatbot/features/llm/domain/local_llm_service.dart';
import 'package:slm_ai_chatbot/features/rag/domain/document_context_builder.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_prompt_builder.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_search_result.dart';
import 'package:slm_ai_chatbot/features/rag/domain/retrieval_query_builder.dart';
import 'package:slm_ai_chatbot/features/rag/domain/retrieved_knowledge_relevance.dart';

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

/// Orchestrates one user question from routing through streaming and history.
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
    RetrievalQueryBuilder? retrievalQueryBuilder,
    ConversationHistory? conversationHistory,
  }) : _ragRepository = ragRepository,
       _llmService = llmService,
       _contextBuilder = contextBuilder,
       _promptBuilder = promptBuilder,
       _intentRouter = intentRouter,
       _conversationalPromptBuilder = conversationalPromptBuilder,
       _relevance = relevance,
       _responseConfiguration = responseConfiguration,
       _retrievalQueryBuilder = retrievalQueryBuilder,
       _conversationHistory =
           conversationHistory ?? InMemoryConversationHistory();

  final RagRepository _ragRepository;
  final LocalLlmService _llmService;
  final DocumentContextBuilder _contextBuilder;
  final RagPromptBuilder _promptBuilder;
  final ChatIntentRouter _intentRouter;
  final ConversationalPromptBuilder _conversationalPromptBuilder;
  final RetrievedKnowledgeRelevance _relevance;
  final ChatResponseConfiguration _responseConfiguration;
  final RetrievalQueryBuilder? _retrievalQueryBuilder;
  final ConversationHistory _conversationHistory;

  Future<void> cancel() => _llmService.stop();

  void clearHistory() => _conversationHistory.clear();

  Future<QuestionAnswer> call(String question) async {
    return stream(question).last;
  }

  /// Emits the complete answer accumulated so far as local generation streams.
  ///
  /// Retrieval and generation failures are emitted as a single controlled
  /// answer, matching [call].
  Stream<QuestionAnswer> stream(
    String question, {
    void Function(Duration)? onGenerationComplete,
    String? turnId,
    bool regenerate = false,
    bool isLatestTurn = false,
  }) async* {
    if (regenerate && turnId == null) {
      throw ArgumentError.notNull('turnId');
    }
    final storedHistory = _conversationHistory.messages;
    final turnIndex = regenerate
        ? storedHistory.indexWhere((message) => message.turnId == turnId)
        : -1;
    // A regenerated turn must not see its old answer or later turns as context.
    // Expired older turns have no safe preceding context in the bounded history.
    final history = !regenerate
        ? storedHistory
        : turnIndex >= 0
        ? storedHistory.sublist(0, turnIndex)
        : isLatestTurn
        ? storedHistory
        : const <ConversationMessage>[];
    final profile = AiLatencyProfile.current;
    if (profile != null) {
      profile.historyMessageCount = history.length;
      profile.historyCharacters = history.isEmpty
          ? 0
          : history.fold<int>(
                  0,
                  (length, message) =>
                      length +
                      message.text.length +
                      (message.author == ConversationAuthor.user ? 6 : 11),
                ) +
                history.length -
                1;
      profile.userQueryCharacters = question.length;
    }
    _debugLog('questionCharacters=${question.length}');
    _debugLog('historyMessageCount=${history.length}');
    profile?.mark(AiProfileEvent.routerStart);
    final ChatRoute route;
    try {
      route = await _routeQuestion(question, history);
    } finally {
      profile?.mark(AiProfileEvent.routerEnd);
    }
    profile?.route = route.label;
    _debugLog('route=${route.label}');
    final answers = switch (route) {
      ChatRoute.chat => _handleChatRequest(
        question,
        history,
        onGenerationComplete,
      ),
      ChatRoute.knowledge => _handleKnowledgeRequest(
        question,
        history,
        onGenerationComplete,
      ),
    };
    QuestionAnswer? lastAnswer;
    await for (final answer in answers) {
      lastAnswer = answer;
      yield answer;
    }
    if (lastAnswer?.status == QuestionAnswerStatus.answered) {
      if (turnIndex >= 0) {
        _conversationHistory.replaceTurn(turnId!, lastAnswer!.answer);
      } else if (!regenerate || isLatestTurn) {
        _conversationHistory.addAll([
          ConversationMessage(
            author: ConversationAuthor.user,
            text: question,
            turnId: turnId,
          ),
          ConversationMessage(
            author: ConversationAuthor.assistant,
            text: lastAnswer!.answer,
            turnId: turnId,
          ),
        ]);
      }
    } else if (turnIndex >= 0 &&
        lastAnswer?.status == QuestionAnswerStatus.noRelevantKnowledge) {
      _conversationHistory.replaceTurn(turnId!, null);
    }
  }

  Stream<QuestionAnswer> _handleChatRequest(
    String question,
    List<ConversationMessage> history,
    void Function(Duration)? onGenerationComplete,
  ) async* {
    final profile = AiLatencyProfile.current;
    profile?.mark(AiProfileEvent.promptBuildStart);
    final prompt = _conversationalPromptBuilder.build(
      question,
      history: history,
    );
    profile?.mark(AiProfileEvent.promptBuildEnd);
    if (profile != null) profile.chatPromptCharacters = prompt.length;
    _debugLog('FALLBACK:\nfalse');
    yield* _generateResponse(prompt, const [], onGenerationComplete);
  }

  Stream<QuestionAnswer> _handleKnowledgeRequest(
    String question,
    List<ConversationMessage> history,
    void Function(Duration)? onGenerationComplete,
  ) async* {
    final profile = AiLatencyProfile.current;
    profile?.mark(AiProfileEvent.retrievalQueryStart);
    final retrievalQuery =
        (_retrievalQueryBuilder ?? const RetrievalQueryBuilder()).build(
          question: question,
          history: history,
        );
    profile?.mark(AiProfileEvent.retrievalQueryEnd);
    profile?.mark(AiProfileEvent.searchStart);
    final searchResults = await _retrieveKnowledge(retrievalQuery);
    profile?.mark(AiProfileEvent.searchEnd);
    if (searchResults == null) {
      _debugLog('RETRIEVED:\nsearch failed');
      _debugLog('FALLBACK:\nfalse');
      _debugLog('FINAL GENERATION:\nfalse');
      yield const QuestionAnswer(
        status: QuestionAnswerStatus.retrievalFailure,
        answer: 'Unable to search the local knowledge base.',
      );
      return;
    }

    if (profile != null) profile.retrievedCount = searchResults.length;
    profile?.mark(AiProfileEvent.groundingStart);
    final documents = _relevance.relevantDocuments(
      question: retrievalQuery,
      results: searchResults,
    );
    profile?.mark(AiProfileEvent.groundingEnd);
    if (profile != null) profile.groundedCount = documents.length;
    _debugLog('retrievedCount=${searchResults.length}');
    _debugLog('groundedCount=${documents.length}');
    if (documents.isEmpty) {
      _debugLog('FALLBACK:\ntrue');
      _debugLog('FINAL GENERATION:\nfalse');
      yield QuestionAnswer(
        status: QuestionAnswerStatus.noRelevantKnowledge,
        answer: _responseConfiguration.unsupportedQuestionMessage,
      );
      return;
    }

    profile?.mark(AiProfileEvent.contextBuildStart);
    final context = _contextBuilder.build(documents);
    profile?.mark(AiProfileEvent.contextBuildEnd);
    if (profile != null) profile.retrievedContextCharacters = context.length;
    profile?.mark(AiProfileEvent.promptBuildStart);
    final prompt = _promptBuilder.build(
      question: question,
      context: context,
      history: history,
    );
    profile?.mark(AiProfileEvent.promptBuildEnd);
    if (profile != null) profile.ragPromptCharacters = prompt.length;
    _debugLog('FALLBACK:\nfalse');
    yield* _generateResponse(prompt, documents, onGenerationComplete);
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[Chat] $message');
    }
  }

  Future<ChatRoute> _routeQuestion(
    String question,
    List<ConversationMessage> history,
  ) async {
    try {
      if (_intentRouter case final HistoryAwareChatIntentRouter router) {
        return await router.routeWithHistory(question, history: history);
      }
      return await _intentRouter.route(question);
    } catch (_) {
      return ChatRoute.knowledge;
    }
  }

  Stream<QuestionAnswer> _generateResponse(
    String prompt,
    List<KnowledgeDocument> documents,
    void Function(Duration)? onGenerationComplete,
  ) async* {
    Duration? completedDuration;
    final profile = AiLatencyProfile.current;
    try {
      _debugLog('FINAL GENERATION:\ntrue');
      final response = StringBuffer();
      profile?.generationPhase = AiGenerationPhase.finalAnswer;
      profile?.mark(AiProfileEvent.finalLlmStart);
      final stopwatch = Stopwatch()..start();
      await for (final chunk in _llmService.generate(prompt)) {
        response.write(chunk);
        yield QuestionAnswer(
          status: QuestionAnswerStatus.answered,
          answer: response.toString(),
          documents: documents,
        );
      }
      stopwatch.stop();
      profile?.mark(AiProfileEvent.finalLlmEnd);
      final answer = response.toString().trim();
      if (answer.isEmpty) {
        yield QuestionAnswer(
          status: QuestionAnswerStatus.generationFailure,
          answer: 'The local AI model did not generate an answer.',
          documents: documents,
        );
        return;
      }
      completedDuration = stopwatch.elapsed;
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
    } finally {
      profile?.mark(AiProfileEvent.finalLlmEnd);
    }
    if (completedDuration != null) {
      onGenerationComplete?.call(completedDuration);
    }
  }

  Future<List<RagSearchResult>?> _retrieveKnowledge(String question) async {
    try {
      _debugLog('retrievalQueryCharacters=${question.length}');
      return await _ragRepository.search(query: question, topK: 3);
    } catch (_) {
      return null;
    }
  }
}
