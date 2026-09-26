import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

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
    _debugLog('CURRENT:\n$question');
    _debugLog('HISTORY:\n${_formatHistory(history)}');
    final route = await _routeQuestion(question, history);
    _debugLog('ROUTER RESULT:\n${route.label}');
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
    final prompt = _conversationalPromptBuilder.build(
      question,
      history: history,
    );
    _debugLog('FALLBACK:\nfalse');
    yield* _generateResponse(prompt, const [], onGenerationComplete);
  }

  Stream<QuestionAnswer> _handleKnowledgeRequest(
    String question,
    List<ConversationMessage> history,
    void Function(Duration)? onGenerationComplete,
  ) async* {
    final retrievalQuery =
        (_retrievalQueryBuilder ?? const RetrievalQueryBuilder()).build(
          question: question,
          history: history,
        );
    final searchResults = await _retrieveKnowledge(retrievalQuery);
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

    final documents = _relevance.relevantDocuments(
      question: retrievalQuery,
      results: searchResults,
    );
    _debugLog('RETRIEVED:\n${_formatSearchResults(searchResults)}');
    _debugLog(
      'GROUNDING:\n${documents.isEmpty ? 'no relevant documents' : 'relevant document IDs: ${documents.map((document) => document.id).join(', ')}'}',
    );
    if (documents.isEmpty) {
      _debugLog('FALLBACK:\ntrue');
      _debugLog('FINAL GENERATION:\nfalse');
      yield QuestionAnswer(
        status: QuestionAnswerStatus.noRelevantKnowledge,
        answer: _responseConfiguration.unsupportedQuestionMessage,
      );
      return;
    }

    final prompt = _promptBuilder.build(
      question: question,
      context: _contextBuilder.build(documents),
      history: history,
    );
    _debugLog('FALLBACK:\nfalse');
    yield* _generateResponse(prompt, documents, onGenerationComplete);
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[Chat] $message');
    }
  }

  String _formatHistory(List<ConversationMessage> history) {
    if (history.isEmpty) return '(empty)';
    return history
        .map(
          (message) =>
              '${message.author == ConversationAuthor.user ? 'User' : 'Assistant'}: ${message.text}',
        )
        .join('\n');
  }

  String _formatSearchResults(List<RagSearchResult> results) {
    if (results.isEmpty) return '(none)';
    return results
        .map(
          (result) =>
              '${result.document.id} | ${result.document.title} | score: ${result.similarity}',
        )
        .join('\n');
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
    try {
      _debugLog('FINAL GENERATION:\ntrue');
      final response = StringBuffer();
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
    }
    if (completedDuration != null) {
      onGenerationComplete?.call(completedDuration);
    }
  }

  Future<List<RagSearchResult>?> _retrieveKnowledge(String question) async {
    try {
      _debugLog('RAG QUERY:\n$question');
      return await _ragRepository.search(query: question, topK: 3);
    } catch (_) {
      return null;
    }
  }
}
