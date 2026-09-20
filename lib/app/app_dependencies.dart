import 'dart:async';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:slm_ai_chatbot/features/chat/data/local_llm_chat_intent_router.dart';
import 'package:slm_ai_chatbot/features/chat/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_response_configuration.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_history.dart';
import 'package:slm_ai_chatbot/features/chat/domain/deterministic_chat_intent_router.dart';
import 'package:slm_ai_chatbot/features/chat/evaluation/data/json_chat_intent_evaluation_dataset_source.dart';
import 'package:slm_ai_chatbot/features/chat/evaluation/domain/chat_intent_evaluation_runner.dart';
import 'package:slm_ai_chatbot/features/chat/evaluation/domain/evaluate_chat_intent_routing_use_case.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/chat_models.dart';
import 'package:slm_ai_chatbot/features/llm/data/local_llm_service_impl.dart';
import 'package:slm_ai_chatbot/features/llm/domain/local_llm_service.dart';
import 'package:slm_ai_chatbot/features/model/data/local_model_repository_impl.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_manager.dart';
import 'package:slm_ai_chatbot/features/rag/data/flutter_gemma_embedding_model_initializer.dart';
import 'package:slm_ai_chatbot/features/rag/data/flutter_gemma_rag_sqlite_repository.dart';
import 'package:slm_ai_chatbot/features/rag/data/json_document_source.dart';
import 'package:slm_ai_chatbot/features/rag/domain/ingest_documents_use_case.dart';
import 'package:slm_ai_chatbot/features/rag/evaluation/data/json_retrieval_evaluation_dataset_source.dart';
import 'package:slm_ai_chatbot/features/rag/evaluation/domain/evaluate_retrieval_use_case.dart';
import 'package:slm_ai_chatbot/features/rag/evaluation/domain/retrieval_evaluation_runner.dart';

class AppDependencies {
  const AppDependencies({
    required this.modelManager,
    required this.askQuestion,
    required this.chatConfiguration,
    required this.chatIntentEvaluationRunner,
    required this.retrievalEvaluationRunner,
    required this.prepareKnowledgeBase,
  });

  final LocalModelManager modelManager;
  final AskQuestionUseCase askQuestion;
  final AiChatConfiguration chatConfiguration;
  final ChatIntentEvaluationRunner chatIntentEvaluationRunner;
  final RetrievalEvaluationRunner retrievalEvaluationRunner;
  final Future<void> Function() prepareKnowledgeBase;
}

Future<AppDependencies> createAppDependencies() async {
  final modelRepository = LocalModelRepositoryImpl(
    downloadToken: const String.fromEnvironment('HUGGING_FACE_TOKEN'),
  );
  const chatConfiguration = AiChatConfiguration();

  // Lifecycle status and inference share one loaded local model.
  final modelManager = LocalModelManager(modelRepository);
  final LocalLlmService llmService = LocalLlmServiceImpl(
    modelProvider: () async => modelRepository.loadedModel,
    releaseModel: modelRepository.releaseLoadedModel,
  );

  // RAG owns EmbeddingGemma preparation and SQLite vector-store access.
  final ragRepository = FlutterGemmaRagSqliteRepository(
    prepareEmbeddingModel: FlutterGemmaEmbeddingModelInitializer(
      downloadToken: const String.fromEnvironment('HUGGING_FACE_TOKEN'),
    ).ensureReady,
    databasePathProvider: () async {
      final directory = await getApplicationSupportDirectory();
      return '${directory.path}/technical_support_rag.db';
    },
  );
  final chatIntentRouter = LocalLlmChatIntentRouter(
    llmService: llmService,
    fallbackRouter: const DeterministicChatIntentRouter(),
  );
  final askQuestion = AskQuestionUseCase(
    ragRepository: ragRepository,
    llmService: llmService,
    intentRouter: chatIntentRouter,
    responseConfiguration: ChatResponseConfiguration(
      greetingMessage: chatConfiguration.greetingMessage,
      wellbeingMessage: chatConfiguration.wellbeingMessage,
      gratitudeMessage: chatConfiguration.gratitudeMessage,
      unsupportedQuestionMessage: chatConfiguration.unsupportedQuestionMessage,
    ),
    conversationHistory: InMemoryConversationHistory(
      maxMessages: chatConfiguration.maxHistoryMessages,
    ),
  );
  final ingestDocuments = IngestDocumentsUseCase(
    documentSource: JsonDocumentSource(assetBundle: rootBundle),
    ragRepository: ragRepository,
  );
  final retrievalEvaluationRunner = RetrievalEvaluationRunner(
    ingestDocuments: ingestDocuments,
    datasetSource: JsonRetrievalEvaluationDatasetSource(
      assetBundle: rootBundle,
    ),
    evaluateRetrieval: EvaluateRetrievalUseCase(ragRepository: ragRepository),
  );
  final chatIntentEvaluationRunner = ChatIntentEvaluationRunner(
    datasetSource: JsonChatIntentEvaluationDatasetSource(
      assetBundle: rootBundle,
    ),
    evaluateRouting: EvaluateChatIntentRoutingUseCase(router: chatIntentRouter),
  );
  unawaited(modelManager.ensureReady());

  return AppDependencies(
    modelManager: modelManager,
    askQuestion: askQuestion,
    chatConfiguration: chatConfiguration,
    chatIntentEvaluationRunner: chatIntentEvaluationRunner,
    retrievalEvaluationRunner: retrievalEvaluationRunner,
    prepareKnowledgeBase: () async => ingestDocuments(),
  );
}
