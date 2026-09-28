import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

import 'package:slm_ai_chatbot/core/profiling/ai_latency_profile.dart';
import '../domain/knowledge_document.dart';
import '../domain/knowledge_identifier_normalizer.dart';
import '../domain/rag_document.dart';
import '../domain/rag_repository.dart';
import '../domain/rag_search_result.dart';

/// Uses EmbeddingGemma and the Flutter Gemma SQLite vector store for RAG.
class FlutterGemmaRagSqliteRepository implements RagRepository {
  static const _documentMetadataKey = '_knowledgeDocument';

  FlutterGemmaRagSqliteRepository({
    required Future<String> Function() databasePathProvider,
    Future<void> Function()? prepareEmbeddingModel,
    FlutterGemmaRagRuntime? runtime,
    KnowledgeIdentifierNormalizer identifierNormalizer =
        const KnowledgeIdentifierNormalizer(),
  }) : _databasePathProvider = databasePathProvider,
       _prepareEmbeddingModel = prepareEmbeddingModel,
       _runtime = runtime ?? FlutterGemmaRagRuntime(),
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

  @override
  Future<void> indexDocuments(Iterable<RagDocument> documents) async {
    await initialize();
    await _prepareEmbeddingModel?.call();
    for (final document in documents) {
      _indexIdentifiers(document.document);
      await _runtime.addDocument(
        id: document.document.id,
        content: document.searchableText,
        metadata: jsonEncode({
          _documentMetadataKey: {
            'title': document.document.title,
            'content': document.document.content,
            if (document.document.measures != null)
              'measures': document.document.measures,
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
    final identifiers = {
      ..._identifierNormalizer.extract(document.id),
      if (document.metadata['code'] case final String code)
        ..._identifierNormalizer.extract(code),
    };
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
      final metadata = document['metadata'];
      if (title is String && content is String && metadata is Map) {
        return KnowledgeDocument(
          id: result.id,
          title: title,
          content: content,
          measures: measures is String ? measures : null,
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

/// Thin adapter around Flutter Gemma's vector-store API.
class FlutterGemmaRagRuntime {
  Future<void> initializeVectorStore(String databasePath) {
    return FlutterGemmaPlugin.instance.initializeVectorStore(databasePath);
  }

  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  }) {
    return FlutterGemmaPlugin.instance.addDocument(
      id: id,
      content: content,
      metadata: metadata,
    );
  }

  Future<List<FlutterGemmaRagRuntimeResult>> searchSimilar({
    required String query,
    required int topK,
    required double threshold,
  }) async {
    final results = await FlutterGemmaPlugin.instance.searchSimilar(
      query: query,
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
