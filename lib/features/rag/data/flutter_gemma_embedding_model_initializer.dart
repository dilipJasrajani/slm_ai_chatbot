import 'package:flutter_gemma/flutter_gemma.dart';

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

  final String? _downloadToken;
  Future<void>? _initialization;

  Future<void> ensureReady() {
    return _initialization ??= _ensureReady();
  }

  Future<void> _ensureReady() async {
    if (!FlutterGemma.hasActiveEmbedder()) {
      await FlutterGemma.installEmbedder()
          .modelFromNetwork(_modelUrl, token: _downloadToken)
          .tokenizerFromNetwork(_tokenizerUrl, token: _downloadToken)
          .install();
    }

    if (FlutterGemmaPlugin.instance.initializedEmbeddingModel == null) {
      await FlutterGemma.getActiveEmbedder(
        preferredBackend: PreferredBackend.cpu,
      );
    }
  }
}
