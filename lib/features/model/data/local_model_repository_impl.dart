import 'package:flutter_gemma/flutter_gemma.dart';

import '../domain/local_model_repository.dart';

class LocalModelRepositoryImpl implements LocalModelRepository {
  LocalModelRepositoryImpl({String? downloadToken})
    : _downloadToken = downloadToken?.trim().isEmpty ?? true
          ? null
          : downloadToken!.trim();

  static const modelFileName = 'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm';
  static const _modelUrl =
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/'
      '$modelFileName';

  final String? _downloadToken;
  InferenceModel? _loadedModel;

  Future<InferenceModel> get loadedModel async {
    return _loadedModel ??= await FlutterGemma.getActiveModel();
  }

  @override
  Future<bool> isInstalled() {
    return FlutterGemma.isModelInstalled(modelFileName);
  }

  @override
  Future<void> download({
    required void Function(int progress) onProgress,
  }) async {
    await FlutterGemma.installModel(
          modelType: ModelType.qwen3,
          fileType: ModelFileType.litertlm,
        )
        .fromNetwork(_modelUrl, token: _downloadToken)
        .withProgress(onProgress)
        .install();
  }

  @override
  Future<void> load() async {
    await loadedModel;
  }

  Future<void> releaseLoadedModel() async {
    final model = _loadedModel;
    _loadedModel = null;
    await model?.close();
  }
}
