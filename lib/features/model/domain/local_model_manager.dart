import 'dart:async';

import 'local_model_repository.dart';
import 'model_status.dart';

class LocalModelManager {
  LocalModelManager(this._repository);

  final LocalModelRepository _repository;
  final StreamController<ModelState> _states =
      StreamController<ModelState>.broadcast();

  ModelState _state = const ModelState.notDownloaded();
  Future<ModelState>? _ongoingOperation;

  ModelState get state => _state;

  Stream<ModelState> get states => _states.stream;

  Future<ModelState> ensureReady() {
    return _ongoingOperation ??= _ensureReady().whenComplete(
      () => _ongoingOperation = null,
    );
  }

  Future<ModelState> _ensureReady() async {
    try {
      final isInstalled = await _repository.isInstalled();

      if (!isInstalled) {
        _emit(const ModelState.notDownloaded());
        _emit(const ModelState.downloading(0));
        await _repository.download(onProgress: _onDownloadProgress);
      }

      _emit(const ModelState.downloaded());
      _emit(const ModelState.loading());
      await _repository.load();
      _emit(const ModelState.ready());
    } catch (error) {
      _emit(ModelState.error(error.toString()));
    }

    return _state;
  }

  void _onDownloadProgress(int progress) {
    _emit(ModelState.downloading(progress));
  }

  void _emit(ModelState state) {
    _state = state;
    _states.add(state);
  }

  Future<void> dispose() => _states.close();
}
