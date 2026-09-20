import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize(
    inferenceEngines: [LiteRtLmEngine()],
    embeddingBackends: const [LiteRtEmbeddingBackend()],
    vectorStore: SqliteVectorStore(),
  );

  final dependencies = await createAppDependencies();

  runApp(
    MyApp(
      modelManager: dependencies.modelManager,
      askQuestion: dependencies.askQuestion,
      chatConfiguration: dependencies.chatConfiguration,
      chatIntentEvaluationRunner: dependencies.chatIntentEvaluationRunner,
      retrievalEvaluationRunner: dependencies.retrievalEvaluationRunner,
      prepareKnowledgeBase: dependencies.prepareKnowledgeBase,
    ),
  );
}
