import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../domain/local_llm_service.dart';
import 'qwen3_output_channel_parser.dart';

class LocalLlmServiceImpl implements LocalLlmService {
  LocalLlmServiceImpl({
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
      enableThinking: false,
    );
    _activeSession = session;

    try {
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      final rawOutput = _logRawOutput(session.getResponseAsync());
      yield* Qwen3OutputChannelParser().parse(rawOutput);
    } finally {
      if (identical(_activeSession, session)) {
        _activeSession = null;
      }

      await session.close();
    }
  }

  Stream<String> _logRawOutput(Stream<String> output) async* {
    await for (final chunk in output) {
      if (kDebugMode) {
        debugPrint('[Qwen] Raw output: $chunk');
      }
      yield chunk;
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
