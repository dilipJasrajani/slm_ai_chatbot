import 'package:flutter/material.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_embeddings/flutter_edge_ai_embeddings.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The local AI runtime must be ready before dependency composition.
  await FlutterEdgeAi.initialize(
    inferenceEngines: [LiteRtLmEngine()],
    embeddingBackends: const [LiteRtEmbeddingBackend()],
    embeddingTokenizers: const [GemmaEmbeddingTokenizers()],
  );

  final dependencies = await createAppDependencies();

  runApp(
    MyApp(
      modelManager: dependencies.modelManager,
      askQuestion: dependencies.askQuestion,
      chatConfiguration: dependencies.chatConfiguration,
      runtimeBackendLabel: dependencies.runtimeBackendLabel,
      chatIntentEvaluationRunner: dependencies.chatIntentEvaluationRunner,
      retrievalEvaluationRunner: dependencies.retrievalEvaluationRunner,
      prepareKnowledgeBase: dependencies.prepareKnowledgeBase,
    ),
  );
}
