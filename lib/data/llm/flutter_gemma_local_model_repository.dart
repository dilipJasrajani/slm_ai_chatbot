import 'package:flutter_gemma/flutter_gemma.dart';

import '../../domain/model/local_model_repository.dart';

class FlutterGemmaLocalModelRepository implements LocalModelRepository {
  FlutterGemmaLocalModelRepository({String? downloadToken})
    : _downloadToken = downloadToken?.trim().isEmpty ?? true
          ? null
          : downloadToken!.trim();

  static const modelFileName = 'gemma3-270m-it-q8.task';
  static const _modelUrl =
      'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/'
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
          modelType: ModelType.gemmaIt,
          fileType: ModelFileType.task,
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
