import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_rag/flutter_edge_ai_rag.dart';
import 'package:flutter_edge_ai_sqlite/flutter_edge_ai_sqlite.dart';

import 'package:slm_ai_chatbot/core/profiling/ai_latency_profile.dart';
import '../domain/knowledge_document.dart';
import '../domain/knowledge_identifier_normalizer.dart';
import '../domain/rag_document.dart';
import '../domain/rag_repository.dart';
import '../domain/rag_search_result.dart';
import 'flutter_gemma_embedding_model_initializer.dart';

/// Uses EmbeddingGemma and the Flutter Gemma SQLite vector store for RAG.
class FlutterGemmaRagSqliteRepository implements RagRepository {
  static const _documentMetadataKey = '_knowledgeDocument';

  FlutterGemmaRagSqliteRepository({
    required Future<String> Function() databasePathProvider,
    Future<void> Function()? prepareEmbeddingModel,
    FlutterGemmaRagRuntime? runtime,
    String embeddingProfileId =
        FlutterGemmaEmbeddingModelInitializer.indexIdentity,
    KnowledgeIdentifierNormalizer identifierNormalizer =
        const KnowledgeIdentifierNormalizer(),
  }) : _databasePathProvider = databasePathProvider,
       _prepareEmbeddingModel = prepareEmbeddingModel,
       _runtime =
           runtime ?? FlutterGemmaRagRuntime(profileId: embeddingProfileId),
       _identifierNormalizer = identifierNormalizer;

  final Future<String> Function() _databasePathProvider;
  final Future<void> Function()? _prepareEmbeddingModel;
  final FlutterGemmaRagRuntime _runtime;
  final KnowledgeIdentifierNormalizer _identifierNormalizer;
  final _documentsByIdentifier = <String, Map<String, KnowledgeDocument>>{};
  Future<void>? _initialization;

  @override
  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    final databasePath = await _databasePathProvider();
    await _runtime.initializeVectorStore(databasePath);
  }

  Future<int> indexedDocumentCount() async {
    await initialize();
    return (await _runtime.getVectorStoreStats()).documentCount;
  }

  Future<void> clearIndex() async {
    await initialize();
    await _runtime.clearVectorStore();
    _documentsByIdentifier.clear();
  }

  void restoreIdentifiers(Iterable<KnowledgeDocument> documents) {
    _documentsByIdentifier.clear();
    for (final document in documents) {
      _indexIdentifiers(document);
    }
  }

  @override
  Future<void> indexDocuments(Iterable<RagDocument> documents) async {
    await initialize();
    await _prepareEmbeddingModel?.call();
    for (final document in documents) {
      _indexIdentifiers(document.document);
      final embedding = await _runtime.embedDocumentText(
        document.searchableText,
      );
      await _runtime.addDocumentWithEmbedding(
        id: document.document.id,
        content: document.document.content,
        embedding: embedding,
        metadata: jsonEncode({
          _documentMetadataKey: {
            'title': document.document.title,
            'content': document.document.content,
            if (document.document.measures != null)
              'measures': document.document.measures,
            if (document.document.searchText != null)
              'searchText': document.document.searchText,
            'metadata': document.document.metadata,
          },
        }),
      );
    }
  }

  @override
  Future<List<RagSearchResult>> search({
    required String query,
    String? exactMatchQuery,
    int topK = 1,
    double threshold = 0.0,
  }) async {
    final profile = AiLatencyProfile.current;
    await initialize();
    await _prepareEmbeddingModel?.call();
    profile?.mark(AiProfileEvent.embeddingAndVectorSearchStart);
    final List<FlutterGemmaRagRuntimeResult> results;
    try {
      results = await _runtime.searchSimilar(
        query: query,
        topK: topK,
        threshold: threshold,
      );
    } finally {
      profile?.mark(AiProfileEvent.embeddingAndVectorSearchEnd);
    }
    profile?.mark(AiProfileEvent.metadataDecodeStart);
    try {
      final exactResults = _exactResults(exactMatchQuery);
      final resultIds = exactResults
          .map((result) => result.document.id)
          .toSet();
      final combinedResults = <RagSearchResult>[...exactResults];
      for (final result in results) {
        final searchResult = RagSearchResult(
          document: _documentFromResult(result),
          similarity: result.similarity,
        );
        if (resultIds.add(searchResult.document.id)) {
          combinedResults.add(searchResult);
        }
      }
      return combinedResults;
    } finally {
      profile?.mark(AiProfileEvent.metadataDecodeEnd);
    }
  }

  void _indexIdentifiers(KnowledgeDocument document) {
    final identifiers = _identifierNormalizer.documentIdentifiers(document);
    for (final identifier in identifiers) {
      (_documentsByIdentifier[identifier] ??= {})[document.id] = document;
    }
  }

  List<RagSearchResult> _exactResults(String? query) {
    if (query == null) return const [];
    final documentsById = <String, KnowledgeDocument>{};
    for (final identifier in _identifierNormalizer.extract(query)) {
      documentsById.addAll(
        _documentsByIdentifier[identifier] ??
            const <String, KnowledgeDocument>{},
      );
    }
    return documentsById.values
        .map((document) => RagSearchResult(document: document, similarity: 1.0))
        .toList(growable: false);
  }

  KnowledgeDocument _documentFromResult(FlutterGemmaRagRuntimeResult result) {
    final storedMetadata = result.metadata == null
        ? const <String, dynamic>{}
        : _decodeMetadata(result.metadata!);
    final storedDocument = storedMetadata[_documentMetadataKey];
    if (storedDocument is Map) {
      final document = Map<String, dynamic>.from(storedDocument);
      final title = document['title'];
      final content = document['content'];
      final measures = document['measures'];
      final searchText = document['searchText'];
      final metadata = document['metadata'];
      if (title is String && content is String && metadata is Map) {
        return KnowledgeDocument(
          id: result.id,
          title: title,
          content: content,
          measures: measures is String ? measures : null,
          searchText: searchText is String ? searchText : null,
          metadata: Map<String, dynamic>.from(metadata),
        );
      }
    }

    return KnowledgeDocument(
      id: result.id,
      title: result.id,
      content: result.content,
      metadata: storedMetadata,
    );
  }

  Map<String, dynamic> _decodeMetadata(String metadata) {
    final decoded = jsonDecode(metadata);
    if (decoded is! Map) {
      throw const FormatException('Stored RAG metadata must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }
}

/// Thin adapter around the profile-bound SQLite vector index.
class FlutterGemmaRagRuntime {
  FlutterGemmaRagRuntime({
    this.profileId = FlutterGemmaEmbeddingModelInitializer.indexIdentity,
    EmbeddingModel? Function()? embeddingModelProvider,
  }) : _embeddingModelProvider =
           embeddingModelProvider ??
           (() => FlutterEdgeAiPlugin.instance.initializedEmbeddingModel);

  final String profileId;
  final EmbeddingModel? Function() _embeddingModelProvider;
  RagIndex? _index;
  static const _embeddingDimension = 768;

  RagIndex get _readyIndex =>
      _index ??
      (throw StateError('The local vector index is not initialized.'));

  Future<List<double>> embedDocumentText(String text) =>
      _embedText(text, TaskType.retrievalDocument);

  Future<List<double>> _embedText(
    String text,
    TaskType taskType, {
    bool keepEnd = false,
  }) async {
    final embeddingModel = _embeddingModelProvider();
    if (embeddingModel == null) {
      throw StateError('The local embedding model is not ready.');
    }
    var input = text;
    while (true) {
      try {
        return await embeddingModel.embed(
          EmbeddingInput.text(input),
          taskType: taskType,
        );
      } on EmbeddingInputTooLongException catch (error) {
        if (input.length <= 1) rethrow;
        final actualTokens = error.actualTokens;
        final fraction =
            actualTokens != null && actualTokens > error.maxInputTokens
            ? (error.maxInputTokens - 4) / actualTokens
            : 0.5;
        final length = (input.length * fraction).floor().clamp(
          1,
          input.length - 1,
        );
        input = keepEnd
            ? input.substring(input.length - length)
            : input.substring(0, length);
      }
    }
  }

  Future<void> initializeVectorStore(String databasePath) async {
    _index =
        await FlutterEdgeAiRag(
          providers: [const SqliteVectorStoreProvider()],
        ).openVectors(
          spec: VectorStoreSpec(
            providerId: SqliteVectorStoreProvider.providerId,
            location: databasePath,
          ),
          profile: EmbeddingProfile(
            id: profileId,
            dimension: _embeddingDimension,
          ),
        );
  }

  Future<void> dispose() async {
    await _index?.dispose();
    _index = null;
  }

  Future<VectorStoreStats> getVectorStoreStats() {
    return _readyIndex.stats();
  }

  Future<void> clearVectorStore() {
    return _readyIndex.clear();
  }

  Future<void> addDocumentWithEmbedding({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) {
    return _readyIndex.addVector(
      id: id,
      content: content,
      embedding: embedding,
      metadata: metadata,
    );
  }

  Future<List<FlutterGemmaRagRuntimeResult>> searchSimilar({
    required String query,
    required int topK,
    required double threshold,
  }) async {
    final queryEmbedding = await _embedText(
      query,
      TaskType.retrievalQuery,
      keepEnd: true,
    );
    final results = await _readyIndex.searchVector(
      embedding: queryEmbedding,
      topK: topK,
      threshold: threshold,
    );
    return results
        .map(
          (result) => FlutterGemmaRagRuntimeResult(
            id: result.id,
            content: result.content,
            similarity: result.similarity,
            metadata: result.metadata,
          ),
        )
        .toList(growable: false);
  }
}

class FlutterGemmaRagRuntimeResult {
  const FlutterGemmaRagRuntimeResult({
    required this.id,
    required this.content,
    required this.similarity,
    this.metadata,
  });

  final String id;
  final String content;
  final double similarity;
  final String? metadata;
}
