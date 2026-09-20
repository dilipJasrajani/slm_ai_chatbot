/// Defines storage, download, and loading operations for the local model.
abstract interface class LocalModelRepository {
  Future<bool> isInstalled();

  Future<void> download({required void Function(int progress) onProgress});

  Future<void> load();
}
