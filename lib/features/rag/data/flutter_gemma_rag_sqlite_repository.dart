import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../domain/knowledge_document.dart';
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
  }) : _databasePathProvider = databasePathProvider,
       _prepareEmbeddingModel = prepareEmbeddingModel,
       _runtime = runtime ?? FlutterGemmaRagRuntime();

  final Future<String> Function() _databasePathProvider;
  final Future<void> Function()? _prepareEmbeddingModel;
  final FlutterGemmaRagRuntime _runtime;
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
      await _runtime.addDocument(
        id: document.document.id,
        content: document.searchableText,
        metadata: jsonEncode({
          _documentMetadataKey: {
            'title': document.document.title,
            'content': document.document.content,
            'metadata': document.document.metadata,
          },
        }),
      );
    }
  }

  @override
  Future<List<RagSearchResult>> search({
    required String query,
    int topK = 1,
    double threshold = 0.0,
  }) async {
    await initialize();
    await _prepareEmbeddingModel?.call();
    final results = await _runtime.searchSimilar(
      query: query,
      topK: topK,
      threshold: threshold,
    );
    return results
        .map(
          (result) => RagSearchResult(
            document: _documentFromResult(result),
            similarity: result.similarity,
          ),
        )
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
      final metadata = document['metadata'];
      if (title is String && content is String && metadata is Map) {
        return KnowledgeDocument(
          id: result.id,
          title: title,
          content: content,
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
