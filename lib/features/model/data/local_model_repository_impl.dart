import 'package:flutter_gemma/flutter_gemma.dart';

import '../domain/local_model_repository.dart';
import 'local_model_configuration.dart';

class LocalModelRepositoryImpl implements LocalModelRepository {
  LocalModelRepositoryImpl({
    required LocalModelConfiguration configuration,
    String? downloadToken,
  }) : _configuration = configuration,
       _downloadToken = downloadToken?.trim().isEmpty ?? true
           ? null
           : downloadToken!.trim();

  final LocalModelConfiguration _configuration;
  final String? _downloadToken;
  InferenceModel? _loadedModel;

  Future<InferenceModel> get loadedModel async {
    return _loadedModel ??= await FlutterGemma.getActiveModel(maxTokens: 2048);
  }

  @override
  Future<bool> isInstalled() {
    return FlutterGemma.isModelInstalled(_configuration.fileName);
  }

  @override
  Future<void> download({
    required void Function(int progress) onProgress,
  }) async {
    await _installer().withProgress(onProgress).install();
  }

  @override
  Future<void> load() async {
    // install() also selects an already-installed model as active after a switch
    // or app restart, without copying or downloading it again.
    await _installer().install();
    await loadedModel;
  }

  InferenceInstallationBuilder _installer() {
    final installer = FlutterGemma.installModel(
      modelType: _configuration.modelType,
      fileType: ModelFileType.litertlm,
    );
    if (_configuration.bundledAsset) {
      return installer.fromAsset(_configuration.source);
    }
    return installer.fromNetwork(_configuration.source, token: _downloadToken);
  }

  Future<void> releaseLoadedModel() async {
    final model = _loadedModel;
    _loadedModel = null;
    await model?.close();
  }
}
