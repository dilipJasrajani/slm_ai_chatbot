import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/data/flutter_gemma_rag_sqlite_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_document.dart';

void main() {
  test('initializes once, indexes documents, and maps search results', () async {
    final runtime = _FakeRagRuntime();
    var embeddingPrepared = 0;
    final repository = FlutterGemmaRagSqliteRepository(
      databasePathProvider: () async => '/local/rag.db',
      prepareEmbeddingModel: () async => embeddingPrepared += 1,
      runtime: runtime,
    );

    await repository.indexDocuments([
      const RagDocument(
        document: KnowledgeDocument(
          id: 'error-e123',
          title: 'Device cannot connect to network',
          content: 'The device failed to establish a network connection.',
          metadata: {'type': 'error', 'code': 'E123'},
        ),
        searchableText: 'Device cannot connect to network',
      ),
    ]);
    final results = await repository.search(
      query: 'The device cannot connect to the network.',
    );

    expect(runtime.databasePaths, ['/local/rag.db']);
    expect(embeddingPrepared, 2);
    expect(runtime.indexedDocuments.single.id, 'error-e123');
    expect(
      runtime.indexedDocuments.single.metadata,
      '{"_knowledgeDocument":{"title":"Device cannot connect to network","content":"The device failed to establish a network connection.","metadata":{"type":"error","code":"E123"}}}',
    );
    expect(runtime.query, 'The device cannot connect to the network.');
    expect(results.single.document.id, 'error-e123');
    expect(results.single.document.title, 'Device cannot connect to network');
    expect(results.single.document.metadata, {'type': 'error', 'code': 'E123'});
  });
}

class _FakeRagRuntime extends FlutterGemmaRagRuntime {
  final databasePaths = <String>[];
  final indexedDocuments = <_IndexedDocument>[];
  String? query;

  @override
  Future<void> initializeVectorStore(String databasePath) async {
    databasePaths.add(databasePath);
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  }) async {
    indexedDocuments.add(
      _IndexedDocument(id: id, content: content, metadata: metadata),
    );
  }

  @override
  Future<List<FlutterGemmaRagRuntimeResult>> searchSimilar({
    required String query,
    required int topK,
    required double threshold,
  }) async {
    this.query = query;
    return const [
      FlutterGemmaRagRuntimeResult(
        id: 'error-e123',
        content: 'Device cannot connect to network',
        similarity: 0.98,
        metadata:
            '{"_knowledgeDocument":{"title":"Device cannot connect to network","content":"The device failed to establish a network connection.","metadata":{"type":"error","code":"E123"}}}',
      ),
    ];
  }
}

class _IndexedDocument {
  const _IndexedDocument({
    required this.id,
    required this.content,
    required this.metadata,
  });

  final String id;
  final String content;
  final String? metadata;
}
