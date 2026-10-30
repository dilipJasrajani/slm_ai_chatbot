import 'dart:async';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/data/flutter_gemma_embedding_model_initializer.dart';

void main() {
  late FlutterEdgeAiPlugin previousPlugin;
  late _FakeModelManager manager;

  setUp(() {
    previousPlugin = FlutterEdgeAiPlugin.instance;
    manager = _FakeModelManager();
    FlutterEdgeAiPlugin.instance = _FakePlugin(manager);
  });

  tearDown(() {
    FlutterEdgeAiPlugin.instance = previousPlugin;
  });

  test('installs both embedding files with foreground downloads', () async {
    final initializer = FlutterGemmaEmbeddingModelInitializer(
      downloadToken: ' test-token ',
    );

    await initializer.ensureReady();

    final spec = manager.installs.single as EmbeddingModelSpec;
    expect(spec.name, 'embeddinggemma-300M_seq256_mixed-precision');
    expect(spec.replacePolicy, ModelReplacePolicy.keep);
    expect(spec.files.map((file) => file.filename), [
      'embeddinggemma-300M_seq256_mixed-precision.tflite',
      'embeddinggemma-300M_seq256_mixed-precision__sentencepiece.model',
    ]);
    final sources = spec.files.map((file) => file.source as NetworkSource);
    expect(sources.map((source) => source.foreground), everyElement(isTrue));
    expect(
      sources.map((source) => source.authToken),
      everyElement('test-token'),
    );
    expect(
      sources.map((source) => source.url).join('|'),
      FlutterGemmaEmbeddingModelInitializer.indexIdentity,
    );
  });

  test('shares an in-flight embedding installation across callers', () async {
    manager.installGate = Completer<void>();
    final initializer = FlutterGemmaEmbeddingModelInitializer();

    final first = initializer.ensureReady();
    final second = initializer.ensureReady();

    expect(identical(first, second), isTrue);
    expect(manager.installs, hasLength(1));
    manager.installGate!.complete();
    await Future.wait([first, second]);
    await initializer.ensureReady();
    expect(manager.installs, hasLength(1));
    expect(
      manager.installs.single.files.map(
        (file) => (file.source as NetworkSource).authToken,
      ),
      everyElement(isNull),
    );
  });

  test('does not reinstall an already active embedder', () async {
    manager.activeEmbeddingModel = EmbeddingModelSpec(
      name: 'existing',
      modelSource: ModelSource.file('/local/existing.tflite'),
      tokenizerSource: ModelSource.file('/local/tokenizer.model'),
    );

    await FlutterGemmaEmbeddingModelInitializer().ensureReady();

    expect(manager.installs, isEmpty);
  });
}

class _FakePlugin extends FlutterEdgeAiPlugin {
  _FakePlugin(this.modelManager);

  @override
  final ModelFileManager modelManager;

  @override
  EmbeddingModel get initializedEmbeddingModel => _FakeEmbeddingModel();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeEmbeddingModel extends EmbeddingModel {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeModelManager implements ModelFileManager {
  final installs = <ModelSpec>[];
  Completer<void>? installGate;

  @override
  ModelSpec? activeEmbeddingModel;

  @override
  Future<void> ensureModelReadyFromSpec(ModelSpec spec) async {
    installs.add(spec);
    await installGate?.future;
    activeEmbeddingModel = spec;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
