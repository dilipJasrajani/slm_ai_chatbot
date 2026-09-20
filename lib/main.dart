import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
import 'package:path_provider/path_provider.dart';

import 'data/llm/flutter_gemma_local_llm_service.dart';
import 'data/llm/flutter_gemma_local_model_repository.dart';
import 'data/rag/flutter_gemma_embedding_model_initializer.dart';
import 'data/rag/flutter_gemma_rag_sqlite_repository.dart';
import 'data/rag/json_document_source.dart';
import 'data/rag/json_retrieval_evaluation_dataset_source.dart';
import 'domain/llm/local_llm_service.dart';
import 'domain/model/local_model_manager.dart';
import 'domain/rag/ask_question_use_case.dart';
import 'domain/rag/chat_response_configuration.dart';
import 'domain/rag/evaluate_retrieval_use_case.dart';
import 'domain/rag/ingest_documents_use_case.dart';
import 'domain/rag/retrieval_evaluation_runner.dart';
import 'presentation/chat/ai_chat_page.dart';
import 'presentation/chat/chat_models.dart';

late final LocalModelManager _modelManager;
late final LocalLlmService _llmService;
late final AskQuestionUseCase _askQuestion;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize(
    inferenceEngines: [MediaPipeEngine()],
    embeddingBackends: const [LiteRtEmbeddingBackend()],
    vectorStore: SqliteVectorStore(),
  );

  final modelRepository = FlutterGemmaLocalModelRepository(
    downloadToken: const String.fromEnvironment('HUGGING_FACE_TOKEN'),
  );
  const chatConfiguration = AiChatConfiguration();
  _modelManager = LocalModelManager(modelRepository);
  _llmService = FlutterGemmaLocalLlmService(
    modelProvider: () async => modelRepository.loadedModel,
    releaseModel: modelRepository.releaseLoadedModel,
  );
  final ragRepository = FlutterGemmaRagSqliteRepository(
    prepareEmbeddingModel: FlutterGemmaEmbeddingModelInitializer(
      downloadToken: const String.fromEnvironment('HUGGING_FACE_TOKEN'),
    ).ensureReady,
    databasePathProvider: () async {
      final directory = await getApplicationSupportDirectory();
      return '${directory.path}/technical_support_rag.db';
    },
  );
  _askQuestion = AskQuestionUseCase(
    ragRepository: ragRepository,
    llmService: _llmService,
    responseConfiguration: ChatResponseConfiguration(
      greetingMessage: chatConfiguration.greetingMessage,
      wellbeingMessage: chatConfiguration.wellbeingMessage,
      gratitudeMessage: chatConfiguration.gratitudeMessage,
      unsupportedQuestionMessage: chatConfiguration.unsupportedQuestionMessage,
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
  unawaited(_modelManager.ensureReady());

  runApp(
    MyApp(
      modelManager: _modelManager,
      askQuestion: _askQuestion,
      chatConfiguration: chatConfiguration,
      retrievalEvaluationRunner: retrievalEvaluationRunner,
      prepareKnowledgeBase: () async => ingestDocuments(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    required this.modelManager,
    required this.askQuestion,
    this.retrievalEvaluationRunner,
    this.prepareKnowledgeBase,
    this.chatConfiguration = const AiChatConfiguration(),
    super.key,
  });

  final LocalModelManager modelManager;
  final AskQuestionUseCase askQuestion;
  final RetrievalEvaluationRunner? retrievalEvaluationRunner;
  final Future<void> Function()? prepareKnowledgeBase;
  final AiChatConfiguration chatConfiguration;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Assistant',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: AiChatPage(
        modelManager: modelManager,
        askQuestion: askQuestion,
        configuration: chatConfiguration,
        prepareKnowledgeBase: prepareKnowledgeBase,
        retrievalEvaluationRunner: retrievalEvaluationRunner,
      ),
    );
  }
}
