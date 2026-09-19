import 'package:flutter_gemma/flutter_gemma.dart';

import '../../domain/llm/local_llm_service.dart';

class FlutterGemmaLocalLlmService implements LocalLlmService {
  FlutterGemmaLocalLlmService({
    required Future<InferenceModel> Function() modelProvider,
    required Future<void> Function() releaseModel,
  }) : _modelProvider = modelProvider,
       _releaseModel = releaseModel;

  final Future<InferenceModel> Function() _modelProvider;
  final Future<void> Function() _releaseModel;
  InferenceModelSession? _activeSession;

  @override
  Stream<String> generate(String prompt) async* {
    if (_activeSession != null) {
      throw StateError('A local response is already being generated.');
    }

    final model = await _modelProvider();
    final session = await model.createSession(
      temperature: 1.0,
      topK: 64,
      topP: 0.95,
    );
    _activeSession = session;

    try {
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      yield* session.getResponseAsync();
    } finally {
      if (identical(_activeSession, session)) {
        _activeSession = null;
      }
      await session.close();
    }
  }

  @override
  Future<void> stop() async {
    await _activeSession?.stopGeneration();
  }

  @override
  Future<void> dispose() async {
    await stop();
    _activeSession = null;
    await _releaseModel();
  }
}
