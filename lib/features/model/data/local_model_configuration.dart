import 'package:flutter_gemma/flutter_gemma.dart';

/// Change [active] to select the inference model for the next app launch.
enum LocalModelConfiguration {
  gemma3(
    fileName: 'gemma3-1b-it.litertlm',
    label: 'Gemma 3 1B · Local',
    modelType: ModelType.gemmaIt,
    source: 'assets/models/gemma3-1b-it.litertlm',
    bundledAsset: true,
  ),
  qwen3(
    fileName: 'Qwen3-0.6B.litertlm',
    label: 'Qwen3 0.6B · Local',
    modelType: ModelType.qwen3,
    source:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/'
        'Qwen3-0.6B.litertlm',
    bundledAsset: false,
  );

  const LocalModelConfiguration({
    required this.fileName,
    required this.label,
    required this.modelType,
    required this.source,
    required this.bundledAsset,
  });

  static const active = qwen3;

  final String fileName;
  final String label;
  final ModelType modelType;
  final String source;
  final bool bundledAsset;

  bool get usesQwen3Output => this == qwen3;
}
