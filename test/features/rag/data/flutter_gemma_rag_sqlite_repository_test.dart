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
    expect(results.single.document.measures, isNull);
    expect(results.single.document.metadata, {'type': 'error', 'code': 'E123'});
  });

  test('preserves measures in stored metadata and search results', () async {
    final runtime = _FakeRagRuntime()
      ..searchResults = const [
        FlutterGemmaRagRuntimeResult(
          id: 'error-e123',
          content: 'Device cannot connect to network',
          similarity: 0.98,
          metadata:
              '{"_knowledgeDocument":{"title":"Device cannot connect to network","content":"The device failed to establish a network connection.","measures":"Check that Wi-Fi is enabled.","metadata":{"type":"error","code":"E123"}}}',
        ),
      ];
    final repository = FlutterGemmaRagSqliteRepository(
      databasePathProvider: () async => '/local/rag.db',
      runtime: runtime,
    );

    await repository.indexDocuments([
      const RagDocument(
        document: KnowledgeDocument(
          id: 'error-e123',
          title: 'Device cannot connect to network',
          content: 'The device failed to establish a network connection.',
          measures: 'Check that Wi-Fi is enabled.',
          metadata: {'type': 'error', 'code': 'E123'},
        ),
        searchableText: 'Device cannot connect to network',
      ),
    ]);
    final results = await repository.search(query: 'network connection');

    expect(
      runtime.indexedDocuments.single.metadata,
      '{"_knowledgeDocument":{"title":"Device cannot connect to network","content":"The device failed to establish a network connection.","measures":"Check that Wi-Fi is enabled.","metadata":{"type":"error","code":"E123"}}}',
    );
    expect(results.single.document.measures, 'Check that Wi-Fi is enabled.');
  });

  test('stores retrieval-only text separately from answer content', () async {
    final runtime = _FakeRagRuntime()
      ..searchResults = const [
        FlutterGemmaRagRuntimeResult(
          id: 'card:msg:f_74',
          content: 'Pressure is low',
          similarity: 0.9,
          metadata:
              '{"_knowledgeDocument":{"title":"FAULT F.74","content":"Pressure is low","searchText":"water gauge low","metadata":{"code":"F.74"}}}',
        ),
      ];
    final repository = FlutterGemmaRagSqliteRepository(
      databasePathProvider: () async => '/local/rag.db',
      runtime: runtime,
    );
    await repository.indexDocuments([
      const RagDocument(
        document: KnowledgeDocument(
          id: 'card:msg:f_74',
          title: 'FAULT F.74',
          content: 'Pressure is low',
          searchText: 'water gauge low',
          metadata: {'code': 'F.74'},
        ),
        searchableText: 'water gauge low\nPressure is low',
      ),
    ]);
    final result = (await repository.search(query: 'water gauge low')).single;

    expect(
      runtime.indexedDocuments.single.metadata,
      contains('"searchText":"water gauge low"'),
    );
    expect(result.document.searchText, 'water gauge low');
    expect(result.document.content, 'Pressure is low');
  });

  test(
    'returns an exact code match before semantic results that omit it',
    () async {
      final runtime = _FakeRagRuntime()
        ..searchResults = const [
          FlutterGemmaRagRuntimeResult(
            id: 'error-e123',
            content: 'Device cannot connect to network',
            similarity: 0.98,
            metadata:
                '{"_knowledgeDocument":{"title":"Device cannot connect to network","content":"The device failed to establish a network connection.","metadata":{"type":"error","code":"E123"}}}',
          ),
          FlutterGemmaRagRuntimeResult(
            id: 'error-e456',
            content: 'Device authentication failed',
            similarity: 0.97,
            metadata:
                '{"_knowledgeDocument":{"title":"Device authentication failed","content":"Check device credentials.","metadata":{"type":"error","code":"E456"}}}',
          ),
        ];
      final repository = FlutterGemmaRagSqliteRepository(
        databasePathProvider: () async => '/local/rag.db',
        runtime: runtime,
      );
      await repository.indexDocuments([
        const RagDocument(
          document: KnowledgeDocument(
            id: 'F.838',
            title: 'Inverter control fault',
            content: 'Control of inverter faulty.',
            metadata: {'type': 'error', 'code': 'F838'},
          ),
          searchableText: 'F838 inverter control fault',
        ),
      ]);

      final results = await repository.search(
        query: 'what is error f838?',
        exactMatchQuery: 'what is error f838?',
        topK: 2,
      );

      expect(runtime.query, 'what is error f838?');
      expect(results.map((result) => result.document.id), [
        'F.838',
        'error-e123',
        'error-e456',
      ]);
      expect(results.first.similarity, 1.0);
    },
  );

  test(
    'normalizes dotted, compact, and lowercase exact code queries',
    () async {
      final runtime = _FakeRagRuntime()..searchResults = const [];
      final repository = FlutterGemmaRagSqliteRepository(
        databasePathProvider: () async => '/local/rag.db',
        runtime: runtime,
      );
      await repository.indexDocuments([
        const RagDocument(
          document: KnowledgeDocument(
            id: 'F.838',
            title: 'Inverter control fault',
            content: 'Control of inverter faulty.',
            metadata: {'type': 'error', 'code': 'F838'},
          ),
          searchableText: 'F838 inverter control fault',
        ),
      ]);

      for (final query in ['F.838', 'F838', 'f838']) {
        final results = await repository.search(
          query: query,
          exactMatchQuery: query,
        );

        expect(results.map((result) => result.document.id), ['F.838']);
      }
    },
  );

  test(
    'keeps semantic-only results for unrelated queries without a code',
    () async {
      final runtime = _FakeRagRuntime();
      final repository = FlutterGemmaRagSqliteRepository(
        databasePathProvider: () async => '/local/rag.db',
        runtime: runtime,
      );
      await repository.indexDocuments([
        const RagDocument(
          document: KnowledgeDocument(
            id: 'F.838',
            title: 'Inverter control fault',
            content: 'Control of inverter faulty.',
            metadata: {'type': 'error', 'code': 'F838'},
          ),
          searchableText: 'F838 inverter control fault',
        ),
      ]);

      final results = await repository.search(
        query: 'How do I connect the device to Wi-Fi?',
      );

      expect(results.map((result) => result.document.id), ['error-e123']);
    },
  );
}

class _FakeRagRuntime extends FlutterGemmaRagRuntime {
  final databasePaths = <String>[];
  final indexedDocuments = <_IndexedDocument>[];
  List<FlutterGemmaRagRuntimeResult> searchResults = const [
    FlutterGemmaRagRuntimeResult(
      id: 'error-e123',
      content: 'Device cannot connect to network',
      similarity: 0.98,
      metadata:
          '{"_knowledgeDocument":{"title":"Device cannot connect to network","content":"The device failed to establish a network connection.","metadata":{"type":"error","code":"E123"}}}',
    ),
  ];
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
    return searchResults;
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
