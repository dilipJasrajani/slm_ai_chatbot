import 'dart:async';

/// Coordinates prerequisite models before indexing local knowledge documents.
class KnowledgeBasePreparation {
  KnowledgeBasePreparation({
    required Future<void> Function() ensureGenerationModelReady,
    required Future<void> Function() ensureEmbeddingModelReady,
    required Future<void> Function() ingestDocuments,
  }) : _ensureGenerationModelReady = ensureGenerationModelReady,
       _ensureEmbeddingModelReady = ensureEmbeddingModelReady,
       _ingestDocuments = ingestDocuments;

  final Future<void> Function() _ensureGenerationModelReady;
  final Future<void> Function() _ensureEmbeddingModelReady;
  final Future<void> Function() _ingestDocuments;

  Future<void>? _generationModelReady;
  Future<void>? _embeddingModelReady;
  Future<void>? _preparation;
  ({Object error, StackTrace stackTrace})? _generationModelFailure;
  ({Object error, StackTrace stackTrace})? _embeddingModelFailure;

  /// Starts both independent model preparations without indexing documents.
  void startModelPreparation() {
    _generationModelReady ??= _captureFailure(
      _ensureGenerationModelReady,
      (failure) => _generationModelFailure = failure,
    );
    _embeddingModelReady ??= _captureFailure(
      _ensureEmbeddingModelReady,
      (failure) => _embeddingModelFailure = failure,
    );
  }

  /// Indexes documents once both the generation and embedding models are ready.
  Future<void> prepareKnowledgeBase() {
    startModelPreparation();
    return _preparation ??= _prepareKnowledgeBase();
  }

  Future<void> _prepareKnowledgeBase() async {
    await Future.wait([_generationModelReady!, _embeddingModelReady!]);
    final failure = _generationModelFailure ?? _embeddingModelFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
    await _ingestDocuments();
  }

  Future<void> _captureFailure(
    Future<void> Function() operation,
    void Function(({Object error, StackTrace stackTrace}) failure) onFailure,
  ) async {
    try {
      await operation();
    } catch (error, stackTrace) {
      onFailure((error: error, stackTrace: stackTrace));
    }
  }
}
