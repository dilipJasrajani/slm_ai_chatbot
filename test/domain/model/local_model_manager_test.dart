import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/domain/model/local_model_manager.dart';
import 'package:slm_ai_chatbot/domain/model/local_model_repository.dart';
import 'package:slm_ai_chatbot/domain/model/model_status.dart';

void main() {
  test(
    'downloads, loads, and reports ready when the model is absent',
    () async {
      final repository = _FakeLocalModelRepository(
        installed: false,
        onDownload: (onProgress) {
          onProgress(40);
          onProgress(100);
        },
      );
      final manager = LocalModelManager(repository);
      final states = <ModelState>[];
      final subscription = manager.states.listen(states.add);

      final result = await manager.ensureReady();
      await Future<void>.delayed(Duration.zero);

      expect(result.status, ModelStatus.ready);
      expect(repository.downloadCalls, 1);
      expect(repository.loadCalls, 1);
      expect(states.map((state) => state.status), [
        ModelStatus.notDownloaded,
        ModelStatus.downloading,
        ModelStatus.downloading,
        ModelStatus.downloading,
        ModelStatus.downloaded,
        ModelStatus.loading,
        ModelStatus.ready,
      ]);
      expect(states[2].downloadProgress, 40);
      expect(states[3].downloadProgress, 100);

      await subscription.cancel();
      await manager.dispose();
    },
  );

  test('loads an installed model without downloading it', () async {
    final repository = _FakeLocalModelRepository(installed: true);
    final manager = LocalModelManager(repository);

    final result = await manager.ensureReady();

    expect(result.status, ModelStatus.ready);
    expect(repository.downloadCalls, 0);
    expect(repository.loadCalls, 1);

    await manager.dispose();
  });

  test('reports an error and does not load when downloading fails', () async {
    final repository = _FakeLocalModelRepository(
      installed: false,
      downloadError: StateError('Authentication required'),
    );
    final manager = LocalModelManager(repository);

    final result = await manager.ensureReady();

    expect(result.status, ModelStatus.error);
    expect(result.errorMessage, contains('Authentication required'));
    expect(repository.loadCalls, 0);

    await manager.dispose();
  });
}

class _FakeLocalModelRepository implements LocalModelRepository {
  _FakeLocalModelRepository({
    required this.installed,
    void Function(void Function(int progress) onProgress)? onDownload,
    this.downloadError,
  }) : _onDownload = onDownload;

  final bool installed;
  final void Function(void Function(int progress) onProgress)? _onDownload;
  final Object? downloadError;
  int downloadCalls = 0;
  int loadCalls = 0;

  @override
  Future<void> download({
    required void Function(int progress) onProgress,
  }) async {
    downloadCalls++;
    if (downloadError != null) {
      throw downloadError!;
    }
    _onDownload?.call(onProgress);
  }

  @override
  Future<bool> isInstalled() async => installed;

  @override
  Future<void> load() async {
    loadCalls++;
  }
}
