import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

import 'data/llm/flutter_gemma_local_llm_service.dart';
import 'data/llm/flutter_gemma_local_model_repository.dart';
import 'domain/llm/local_llm_service.dart';
import 'domain/model/local_model_manager.dart';
import 'presentation/local_inference_screen.dart';

late final LocalModelManager _modelManager;
late final LocalLlmService _llmService;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize(inferenceEngines: [MediaPipeEngine()]);

  final modelRepository = FlutterGemmaLocalModelRepository(
    downloadToken: const String.fromEnvironment('HUGGING_FACE_TOKEN'),
  );
  _modelManager = LocalModelManager(modelRepository);
  _llmService = FlutterGemmaLocalLlmService(
    modelProvider: () async => modelRepository.loadedModel,
    releaseModel: modelRepository.releaseLoadedModel,
  );
  unawaited(_modelManager.ensureReady());

  runApp(MyApp(modelManager: _modelManager, llmService: _llmService));
}

class MyApp extends StatelessWidget {
  const MyApp({
    required this.modelManager,
    required this.llmService,
    super.key,
  });

  final LocalModelManager modelManager;
  final LocalLlmService llmService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Gemma Test',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: LocalInferenceScreen(
        modelManager: modelManager,
        llmService: llmService,
      ),
    );
  }
}
