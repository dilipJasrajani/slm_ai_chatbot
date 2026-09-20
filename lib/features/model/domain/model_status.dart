enum ModelStatus {
  notDownloaded,
  downloading,
  downloaded,
  loading,
  ready,
  error,
}

class ModelState {
  const ModelState._({
    required this.status,
    this.downloadProgress,
    this.errorMessage,
  });

  const ModelState.notDownloaded() : this._(status: ModelStatus.notDownloaded);

  const ModelState.downloading(int progress)
    : this._(status: ModelStatus.downloading, downloadProgress: progress);

  const ModelState.downloaded() : this._(status: ModelStatus.downloaded);

  const ModelState.loading() : this._(status: ModelStatus.loading);

  const ModelState.ready() : this._(status: ModelStatus.ready);

  const ModelState.error(String message)
    : this._(status: ModelStatus.error, errorMessage: message);

  final ModelStatus status;
  final int? downloadProgress;
  final String? errorMessage;
}
