import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/data/json_document_directory_source.dart';
import 'package:slm_ai_chatbot/features/rag/domain/ingest_documents_use_case.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_search_result.dart';

const _directory = 'assets/knowledge_base/';
const _errors = '${_directory}documents.json';
const _greetings = '${_directory}greeting-document.json';
const _linked = '${_directory}kb_linked_mobile.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('discovers and loads two JSON files', () async {
    final source = _source(
      _ManifestAssetBundle({
        _errors: _json(['error-e123']),
        _greetings: _json(['greeting-hello']),
      }),
    );

    expect((await source.loadDocuments()).map((document) => document.id), [
      'error-e123',
      'greeting-hello',
    ]);
  });

  test('loads multiple documents from one JSON file', () async {
    final source = _source(
      _ManifestAssetBundle({
        _errors: _json(['error-e123', 'error-e456']),
      }),
    );

    expect((await source.loadDocuments()).map((document) => document.id), [
      'error-e123',
      'error-e456',
    ]);
  });

  test('combines multiple documents from multiple files', () async {
    final source = _source(
      _ManifestAssetBundle({
        _errors: _json(['error-e123', 'error-e456']),
        _greetings: _json(['greeting-hi', 'greeting-hello']),
      }),
    );

    expect((await source.loadDocuments()).map((document) => document.id), [
      'error-e123',
      'error-e456',
      'greeting-hi',
      'greeting-hello',
    ]);
  });

  test(
    'combines legacy documents with linked and unknown-schema records',
    () async {
      final source = _source(
        _ManifestAssetBundle({
          _errors: _json(['error-e123']),
          _linked: jsonEncode({
            'entries': [
              {
                'id': 'card:msg:f_74',
                'title': 'FAULT F.74',
                'text': 'Code: F.74\nCause: Pressure too low',
              },
            ],
          }),
          '${_directory}future.json': jsonEncode([
            {'name': 'Pump', 'description': 'Pump maintenance'},
          ]),
        }),
      );

      final documents = await source.loadDocuments();

      expect(documents.map((document) => document.id), [
        'error-e123',
        '${_directory}future.json#0',
        'card:msg:f_74',
      ]);
    },
  );

  test('loads files in sorted asset-path order', () async {
    final bundle = _ManifestAssetBundle({
      _greetings: _json(['greeting-hello']),
      _errors: _json(['error-e123']),
    });

    final documents = await _source(bundle).loadDocuments();

    expect(bundle.loadedJsonPaths, [_errors, _greetings]);
    expect(documents.map((document) => document.id), [
      'error-e123',
      'greeting-hello',
    ]);
  });

  test('ignores non-JSON and out-of-directory assets', () async {
    final bundle = _ManifestAssetBundle({
      '${_directory}notes.txt': 'not JSON',
      'assets/evaluation/cases.json': '{',
      _errors: _json(['error-e123']),
    });

    expect((await _source(bundle).loadDocuments()).single.id, 'error-e123');
    expect(bundle.loadedJsonPaths, [_errors]);
  });

  test('ignores JSON in nested directories', () async {
    final bundle = _ManifestAssetBundle({
      '${_directory}nested/invalid.json': '{',
      _errors: _json(['error-e123']),
    });

    expect((await _source(bundle).loadDocuments()).single.id, 'error-e123');
    expect(bundle.loadedJsonPaths, [_errors]);
  });

  test('malformed JSON fails before indexing any documents', () async {
    final bundle = _ManifestAssetBundle({
      _errors: _json(['error-e123']),
      _greetings: '{',
    });
    final repository = _RecordingRagRepository();
    final ingest = IngestDocumentsUseCase(
      documentSource: _source(bundle),
      ragRepository: repository,
    );

    await expectLater(
      ingest(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains(_greetings),
        ),
      ),
    );
    expect(repository.indexedIds, isEmpty);
  });

  test('invalid document schema fails before indexing', () async {
    final bundle = _ManifestAssetBundle({
      _errors: _json(['error-e123']),
      _greetings: jsonEncode({
        'version': 1,
        'documents': [
          {'id': 'greeting-hello', 'content': 'Hello', 'metadata': {}},
        ],
      }),
    });
    final repository = _RecordingRagRepository();
    final ingest = IngestDocumentsUseCase(
      documentSource: _source(bundle),
      ragRepository: repository,
    );

    await expectLater(
      ingest(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains(_greetings),
        ),
      ),
    );
    expect(repository.indexedIds, isEmpty);
  });

  test('no JSON assets produces a clear error', () async {
    final source = _source(
      _ManifestAssetBundle({
        '${_directory}notes.txt': 'not JSON',
        '${_directory}nested/documents.json': _json(['nested']),
      }),
    );

    await expectLater(
      source.loadDocuments(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(_directory),
        ),
      ),
    );
  });

  test(
    'empty documents lists retain the single-file parser behavior',
    () async {
      final source = _source(
        _ManifestAssetBundle({
          _errors: _json([]),
          _greetings: _json(['greeting-hello']),
        }),
      );

      expect((await source.loadDocuments()).single.id, 'greeting-hello');
    },
  );

  test('missing listed JSON asset fails rather than being skipped', () async {
    final source = _source(
      _ManifestAssetBundle(
        {
          _errors: _json(['error-e123']),
        },
        paths: [_errors, _greetings],
      ),
    );

    await expectLater(
      source.loadDocuments(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(_greetings),
        ),
      ),
    );
  });

  test('duplicate IDs identify both assets before indexing', () async {
    final bundle = _ManifestAssetBundle({
      _errors: _json(['error-e123']),
      _greetings: _json(['error-e123']),
    });
    final repository = _RecordingRagRepository();
    final ingest = IngestDocumentsUseCase(
      documentSource: _source(bundle),
      ragRepository: repository,
    );

    await expectLater(
      ingest(),
      throwsA(
        isA<FormatException>()
            .having((error) => error.message, 'message', contains('error-e123'))
            .having((error) => error.message, 'first path', contains(_errors))
            .having(
              (error) => error.message,
              'second path',
              contains(_greetings),
            ),
      ),
    );
    expect(repository.indexedIds, isEmpty);
  });

  test('bundled JSON files persist all documents in SQLite', () async {
    final source = _source(rootBundle);
    final documents = await source.loadDocuments();
    expect(documents, isNotEmpty);
    expect(
      documents.map((document) => document.id).toSet(),
      hasLength(documents.length),
    );
    expect(documents.any((document) => document.id == 'card:msg:f_74'), isTrue);
    final greetings = await rootBundle.loadString(_greetings);
    expect(
      (jsonDecode(greetings) as Map<String, dynamic>)['documents'],
      hasLength(9),
    );

    final directory = await Directory.systemTemp.createTemp(
      'knowledge_ingest_',
    );
    final store = SqliteVectorStore();
    try {
      await store.initialize('${directory.path}/knowledge.db');
      final result = await IngestDocumentsUseCase(
        documentSource: source,
        ragRepository: _RecordingRagRepository(store: store),
      )();

      expect(result.documentCount, documents.length);
      expect((await store.getStats()).documentCount, documents.length);
    } finally {
      await store.close();
      await directory.delete(recursive: true);
    }
  });
}

JsonDocumentDirectorySource _source(AssetBundle bundle) {
  return JsonDocumentDirectorySource(
    assetBundle: bundle,
    assetDirectory: _directory,
  );
}

String _json(List<String> ids) {
  return jsonEncode({
    'version': 1,
    'documents': [
      for (final id in ids)
        {
          'id': id,
          'title': id,
          'content': 'Description for $id',
          'metadata': <String, Object>{},
        },
    ],
  });
}

class _ManifestAssetBundle extends CachingAssetBundle {
  _ManifestAssetBundle(this.contents, {List<String>? paths})
    : paths = paths ?? contents.keys.toList();

  final Map<String, String> contents;
  final List<String> paths;
  final loadedJsonPaths = <String>[];

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        for (final path in paths)
          path: [
            {'asset': path},
          ],
      })!;
    }
    final content = contents[key];
    if (content == null) {
      throw FlutterError('Unable to load asset: "$key"');
    }
    loadedJsonPaths.add(key);
    return ByteData.sublistView(utf8.encode(content));
  }
}

class _RecordingRagRepository implements RagRepository {
  _RecordingRagRepository({this.store});

  final SqliteVectorStore? store;
  final indexedIds = <String>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> indexDocuments(Iterable<RagDocument> documents) async {
    for (final document in documents) {
      indexedIds.add(document.document.id);
      await store?.addDocument(
        id: document.document.id,
        content: document.document.content,
        embedding: [1.0, 0.0, 0.0],
      );
    }
  }

  @override
  Future<List<RagSearchResult>> search({
    required String query,
    String? exactMatchQuery,
    int topK = 1,
    double threshold = 0.0,
  }) async => [];
}
