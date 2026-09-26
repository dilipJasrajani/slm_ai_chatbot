import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'package:slm_ai_chatbot/core/profiling/ai_latency_profile.dart';
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
    final profile = AiLatencyProfile.current;
    final generationPhase = profile?.generationPhase;
    if (_activeSession != null) {
      throw StateError('A local response is already being generated.');
    }

    final model = await _modelProvider();
    if (profile != null) {
      profile.backend = model.activeBackend?.name.toUpperCase() ?? 'UNKNOWN';
    }
    final session = await model.createSession(
      temperature: 1.0,
      topK: 64,
      topP: 0.95,
      enableThinking: false,
    );
    _activeSession = session;

    try {
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      final rawOutput = _logRawOutput(
        session.getResponseAsync(),
        profile: profile,
        phase: generationPhase,
      );
      final parsedOutput = Qwen3OutputChannelParser().parse(rawOutput);
      yield* profile == null
          ? parsedOutput
          : parsedOutput.map((chunk) {
              profile.firstParsedChunk(generationPhase, chunk);
              return chunk;
            });
      if (profile != null) {
        try {
          final metrics = session.getSessionMetrics();
          if (metrics.totalTokens > 0 ||
              metrics.timeToFirstTokenMs != null ||
              metrics.tokensPerSecond != null ||
              metrics.initTimeMs != null) {
            profile.recordNativeMetrics(
              generationPhase,
              AiNativeMetrics(
                inputTokens: metrics.inputTokens > 0
                    ? metrics.inputTokens
                    : null,
                outputTokens: metrics.totalTokens > 0
                    ? metrics.outputTokens
                    : null,
                timeToFirstTokenMs: metrics.timeToFirstTokenMs,
                tokensPerSecond: metrics.tokensPerSecond,
                initTimeMs: metrics.initTimeMs,
              ),
            );
          } else {
            profile.nativeMetricsUnavailable(
              generationPhase,
              'SDK returned no benchmark data',
            );
          }
        } on StateError {
          profile.nativeMetricsUnavailable(generationPhase, 'StateError');
        } on UnsupportedError {
          profile.nativeMetricsUnavailable(generationPhase, 'UnsupportedError');
        } on Exception catch (error) {
          profile.nativeMetricsUnavailable(
            generationPhase,
            error.runtimeType.toString(),
          );
        }
      }
    } finally {
      if (identical(_activeSession, session)) {
        _activeSession = null;
      }

      await session.close();
    }
  }

  Stream<String> _logRawOutput(
    Stream<String> output, {
    AiLatencyProfile? profile,
    AiGenerationPhase? phase,
  }) async* {
    await for (final chunk in output) {
      profile?.firstRawChunk(phase);
      if (kDebugMode && profile == null) {
        debugPrint('[Qwen] Raw chunk characters: ${chunk.length}');
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
