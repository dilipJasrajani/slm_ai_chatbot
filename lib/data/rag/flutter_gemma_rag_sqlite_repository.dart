import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../../domain/rag/rag_document.dart';
import '../../domain/rag/rag_repository.dart';
import '../../domain/rag/rag_search_result.dart';

class FlutterGemmaRagSqliteRepository implements RagRepository {
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
        id: document.id,
        content: document.content,
        metadata: document.metadata == null
            ? null
            : jsonEncode(document.metadata),
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
            id: result.id,
            content: result.content,
            similarity: result.similarity,
            metadata: result.metadata == null
                ? null
                : Map<String, String>.from(
                    jsonDecode(result.metadata!) as Map<String, dynamic>,
                  ),
          ),
        )
        .toList(growable: false);
  }
}

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
