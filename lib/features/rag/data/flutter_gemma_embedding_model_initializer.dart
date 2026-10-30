import 'package:flutter_edge_ai/flutter_edge_ai.dart';

/// Ensures the local EmbeddingGemma model is installed and active for RAG.
class FlutterGemmaEmbeddingModelInitializer {
  FlutterGemmaEmbeddingModelInitializer({String? downloadToken})
    : _downloadToken = downloadToken?.trim().isEmpty ?? true
          ? null
          : downloadToken!.trim();

  static const _modelUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/'
      'embeddinggemma-300M_seq256_mixed-precision.tflite';
  static const _tokenizerUrl =
      'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/'
      'sentencepiece.model';
  static const indexIdentity = '$_modelUrl|$_tokenizerUrl';

  final String? _downloadToken;
  Future<void>? _initialization;

  Future<void> ensureReady() {
    return _initialization ??= _ensureReady();
  }

  Future<void> _ensureReady() async {
    if (!FlutterEdgeAi.hasActiveEmbedder()) {
      // The embedding builder in flutter_edge_ai 2.4.1 cannot set foreground.
      // The spec API preserves installation identities and activates the model.
      await FlutterEdgeAiPlugin.instance.modelManager.ensureModelReadyFromSpec(
        EmbeddingModelSpec(
          name: 'embeddinggemma-300M_seq256_mixed-precision',
          modelSource: ModelSource.network(
            _modelUrl,
            authToken: _downloadToken,
            foreground: true,
          ),
          tokenizerSource: ModelSource.network(
            _tokenizerUrl,
            authToken: _downloadToken,
            foreground: true,
          ),
        ),
      );
    }

    if (FlutterEdgeAiPlugin.instance.initializedEmbeddingModel == null) {
      await FlutterEdgeAi.getActiveEmbedder(
        preferredBackend: PreferredBackend.cpu,
      );
    }
  }
}
