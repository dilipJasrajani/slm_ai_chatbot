import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/data/flutter_gemma_rag_sqlite_repository.dart';
import 'package:slm_ai_chatbot/features/rag/data/json_document_directory_source.dart';
import 'package:slm_ai_chatbot/features/rag/data/persistent_knowledge_index.dart';
import 'package:slm_ai_chatbot/features/rag/domain/ingest_documents_use_case.dart';

const _assetDirectory = 'assets/knowledge_base/';
const _assetPath = '${_assetDirectory}knowledge.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late String databasePath;
  late _SqliteRuntime runtime;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cached_knowledge_');
    databasePath = '${directory.path}/knowledge.db';
    runtime = _SqliteRuntime();
  });

  tearDown(() async {
    await runtime.close();
    await directory.delete(recursive: true);
  });

  test(
    'restarts reuse persisted vectors and restore exact-code lookup',
    () async {
      final bundle = _AssetBundle(_documents(['F.74', 'F.1']));
      final first = _preparation(bundle, runtime, databasePath);
      await first.index.prepare();
      expect(runtime.adds, 2);
      expect(await first.repository.indexedDocumentCount(), 2);

      await runtime.close();
      runtime = _SqliteRuntime();
      final second = _preparation(bundle, runtime, databasePath);
      await second.index.prepare();

      expect(runtime.adds, 0);
      expect(runtime.clears, 0);
      expect(
        (await second.repository.search(
          query: 'What is F74?',
          exactMatchQuery: 'What is F74?',
        )).first.document.id,
        'F.74',
      );
    },
  );

  test('content edits rebuild without leaving removed entries', () async {
    await _preparation(
      _AssetBundle(_documents(['F.74', 'F.1'])),
      runtime,
      databasePath,
    ).index.prepare();
    final changed = _preparation(
      _AssetBundle(_documents(['F.74'])),
      runtime,
      databasePath,
    );
    await changed.index.prepare();

    expect(runtime.clears, 2);
    expect(runtime.adds, 3);
    expect(await changed.repository.indexedDocumentCount(), 1);
    expect(
      await changed.repository.search(query: 'F1', exactMatchQuery: 'F1'),
      isEmpty,
    );
  });

  test(
    'embeds search_text but stores the complete nested JSON record',
    () async {
      final record = {
        'id': 'card:msg:f_74',
        'title': 'FAULT F.74',
        'text': 'Cause: Pressure too low',
        'search_text': 'F.74 low pressure',
        'measures': [
          {'text': 'Refill the system'},
        ],
        'fix_procedures': [
          {'id': 'card:proc:refill'},
        ],
      };
      final fallbackRecord = {
        'id': 'card:proc:refill',
        'title': 'Refill the system',
        'steps': ['Check pressure', 'Refill'],
      };
      final bundle = _AssetBundle(
        jsonEncode({
          'entries': [record, fallbackRecord],
        }),
      );
      await _preparation(bundle, runtime, databasePath).index.prepare();

      expect(runtime.embeddedTexts, [
        'F.74 low pressure',
        jsonEncode(fallbackRecord),
      ]);
      final stored = await runtime.store.searchSimilar(
        queryEmbedding: [1, 0, 0],
        topK: 2,
      );
      expect(
        stored.map((result) => jsonDecode(result.content)),
        containsAll([record, fallbackRecord]),
      );
    },
  );

  test(
    'same-size knowledge changes still invalidate the fingerprint',
    () async {
      await _preparation(
        _AssetBundle(_documents(['F.74'])),
        runtime,
        databasePath,
      ).index.prepare();

      await _preparation(
        _AssetBundle(_documents(['F.75'])),
        runtime,
        databasePath,
      ).index.prepare();

      expect(runtime.adds, 2);
      expect(runtime.clears, 2);
    },
  );

  test('embedding identity changes invalidate the cached index', () async {
    final bundle = _AssetBundle(_documents(['F.74']));
    await _preparation(bundle, runtime, databasePath).index.prepare();
    await _preparation(
      bundle,
      runtime,
      databasePath,
      embeddingIdentity: 'different-embedding-model',
    ).index.prepare();

    expect(runtime.adds, 2);
    expect(runtime.clears, 2);
  });

  test('concurrent preparation indexes each record only once', () async {
    final preparation = _preparation(
      _AssetBundle(_documents(['F.74', 'F.1'])),
      runtime,
      databasePath,
    );

    await Future.wait([
      preparation.index.prepare(),
      preparation.index.prepare(),
    ]);

    expect(runtime.adds, 2);
    expect(runtime.clears, 1);
  });

  test('incomplete database rebuilds even with a matching marker', () async {
    final bundle = _AssetBundle(_documents(['F.74', 'F.1']));
    await _preparation(bundle, runtime, databasePath).index.prepare();
    await runtime.store.clear();

    await _preparation(bundle, runtime, databasePath).index.prepare();

    expect(runtime.adds, 4);
    expect((await runtime.store.getStats()).documentCount, 2);
  });

  test(
    'invalid cache marker rebuilds instead of blocking local knowledge',
    () async {
      final bundle = _AssetBundle(_documents(['F.74']));
      await _preparation(bundle, runtime, databasePath).index.prepare();
      await File('$databasePath.index.json').writeAsString('{');

      await _preparation(bundle, runtime, databasePath).index.prepare();

      expect(runtime.adds, 2);
      expect((await runtime.store.getStats()).documentCount, 1);
    },
  );

  test('missing database or incomplete index triggers a rebuild', () async {
    final bundle = _AssetBundle(_documents(['F.74', 'F.1']));
    await _preparation(bundle, runtime, databasePath).index.prepare();
    await runtime.close();
    await File(databasePath).delete();
    runtime = _SqliteRuntime();

    final rebuilt = _preparation(bundle, runtime, databasePath);
    await rebuilt.index.prepare();

    expect(runtime.adds, 2);
    expect(await rebuilt.repository.indexedDocumentCount(), 2);
  });

  test('failed indexing never marks a partial index as complete', () async {
    final bundle = _AssetBundle(_documents(['F.74', 'F.1']));
    runtime.failOnAdd = 2;
    final attempted = _preparation(bundle, runtime, databasePath);

    await expectLater(attempted.index.prepare(), throwsStateError);
    expect(await attempted.repository.indexedDocumentCount(), 1);
    expect(await File('$databasePath.index.json').exists(), isFalse);

    runtime.failOnAdd = null;
    await _preparation(bundle, runtime, databasePath).index.prepare();

    expect(await attempted.repository.indexedDocumentCount(), 2);
    expect(runtime.clears, 2);
  });
}

({PersistentKnowledgeIndex index, FlutterGemmaRagSqliteRepository repository})
_preparation(
  _AssetBundle bundle,
  _SqliteRuntime runtime,
  String databasePath, {
  String embeddingIdentity = 'embedding-v1',
}) {
  final repository = FlutterGemmaRagSqliteRepository(
    databasePathProvider: () async => databasePath,
    runtime: runtime,
  );
  final source = JsonDocumentDirectorySource(
    assetBundle: bundle,
    assetDirectory: _assetDirectory,
  );
  return (
    repository: repository,
    index: PersistentKnowledgeIndex(
      assetBundle: bundle,
      assetDirectory: _assetDirectory,
      databasePath: databasePath,
      embeddingIdentity: embeddingIdentity,
      documentSource: source,
      ingestDocuments: IngestDocumentsUseCase(
        documentSource: source,
        ragRepository: repository,
      ),
      ragRepository: repository,
    ),
  );
}

String _documents(List<String> codes) => jsonEncode({
  'version': 1,
  'documents': [
    for (final code in codes)
      {
        'id': code,
        'title': 'Fault $code',
        'content': 'Information for $code',
        'metadata': {'code': code},
      },
  ],
});

class _AssetBundle extends CachingAssetBundle {
  _AssetBundle(this.json);

  final String json;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        _assetPath: [
          {'asset': _assetPath},
        ],
      })!;
    }
    if (key != _assetPath) throw FlutterError('Unknown asset "$key".');
    return ByteData.sublistView(utf8.encode(json));
  }
}

class _SqliteRuntime extends FlutterGemmaRagRuntime {
  final store = SqliteVectorStore();
  final embeddedTexts = <String>[];
  var adds = 0;
  var clears = 0;
  int? failOnAdd;

  @override
  Future<List<double>> embedDocumentText(String text) async {
    embeddedTexts.add(text);
    return [1, 0, 0];
  }

  @override
  Future<void> initializeVectorStore(String path) => store.initialize(path);

  @override
  Future<VectorStoreStats> getVectorStoreStats() => store.getStats();

  @override
  Future<void> clearVectorStore() async {
    clears++;
    await store.clear();
  }

  @override
  Future<void> addDocumentWithEmbedding({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    adds++;
    if (adds == failOnAdd) throw StateError('Embedding failed.');
    await store.addDocument(
      id: id,
      content: content,
      embedding: embedding,
      metadata: metadata,
    );
  }

  @override
  Future<List<FlutterGemmaRagRuntimeResult>> searchSimilar({
    required String query,
    required int topK,
    required double threshold,
  }) async => [];

  Future<void> close() => store.close();
}
