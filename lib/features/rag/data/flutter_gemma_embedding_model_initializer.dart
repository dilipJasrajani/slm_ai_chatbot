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
      await FlutterEdgeAi.installEmbedder()
          .modelFromNetwork(_modelUrl, token: _downloadToken)
          .tokenizerFromNetwork(_tokenizerUrl, token: _downloadToken)
          .install();
    }

    if (FlutterEdgeAiPlugin.instance.initializedEmbeddingModel == null) {
      await FlutterEdgeAi.getActiveEmbedder(
        preferredBackend: PreferredBackend.cpu,
      );
    }
  }
}
