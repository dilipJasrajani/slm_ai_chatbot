import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
import 'package:path_provider/path_provider.dart';

import 'data/llm/flutter_gemma_local_llm_service.dart';
import 'data/llm/flutter_gemma_local_model_repository.dart';
import 'data/rag/flutter_gemma_embedding_model_initializer.dart';
import 'data/rag/flutter_gemma_rag_sqlite_repository.dart';
import 'domain/llm/local_llm_service.dart';
import 'domain/model/local_model_manager.dart';
import 'domain/rag/technical_support_rag_proof_of_concept.dart';
import 'presentation/local_inference_screen.dart';

late final LocalModelManager _modelManager;
late final LocalLlmService _llmService;
late final TechnicalSupportRagProofOfConcept _ragProofOfConcept;

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
  _modelManager = LocalModelManager(modelRepository);
  _llmService = FlutterGemmaLocalLlmService(
    modelProvider: () async => modelRepository.loadedModel,
    releaseModel: modelRepository.releaseLoadedModel,
  );
  _ragProofOfConcept = TechnicalSupportRagProofOfConcept(
    FlutterGemmaRagSqliteRepository(
      prepareEmbeddingModel: FlutterGemmaEmbeddingModelInitializer(
        downloadToken: const String.fromEnvironment('HUGGING_FACE_TOKEN'),
      ).ensureReady,
      databasePathProvider: () async {
        final directory = await getApplicationSupportDirectory();
        return '${directory.path}/technical_support_rag.db';
      },
    ),
  );
  unawaited(_modelManager.ensureReady());

  runApp(
    MyApp(
      modelManager: _modelManager,
      llmService: _llmService,
      ragProofOfConcept: _ragProofOfConcept,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    required this.modelManager,
    required this.llmService,
    required this.ragProofOfConcept,
    super.key,
  });

  final LocalModelManager modelManager;
  final LocalLlmService llmService;
  final TechnicalSupportRagProofOfConcept ragProofOfConcept;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Gemma Test',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: LocalInferenceScreen(
        modelManager: modelManager,
        llmService: llmService,
        ragProofOfConcept: ragProofOfConcept,
      ),
    );
  }
}
