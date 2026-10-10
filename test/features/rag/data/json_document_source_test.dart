import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/data/json_document_source.dart';

void main() {
  test('parses valid JSON with multiple documents', () async {
    final source = JsonDocumentSource(
      assetBundle: _StringAssetBundle(_knowledgeBaseJson()),
    );

    final documents = await source.loadDocuments();

    expect(documents, hasLength(2));
    expect(documents.first.id, 'error-e123');
    expect(
      documents.first.measures,
      'Check that the device has network access.',
    );
    expect(documents.last.metadata['code'], 'E456');
    expect(documents.last.metadata['type'], 'error');
    expect(documents.last.measures, isNull);
    expect(
      jsonDecode(documents.first.content),
      _document(measures: 'Check that the device has network access.'),
    );
  });

  test('rejects a document with a missing required field', () {
    final document = _document();
    document.remove('title');
    final source = JsonDocumentSource(
      assetBundle: _StringAssetBundle(
        jsonEncode({
          'version': 1,
          'documents': [document],
        }),
      ),
    );

    expect(source.loadDocuments, throwsFormatException);
  });

  test('rejects malformed JSON', () {
    final source = JsonDocumentSource(assetBundle: _StringAssetBundle('{'));

    expect(source.loadDocuments, throwsFormatException);
  });

  test('accepts an empty documents list', () async {
    final source = JsonDocumentSource(
      assetBundle: _StringAssetBundle(
        jsonEncode({'version': 1, 'documents': []}),
      ),
    );

    final documents = await source.loadDocuments();

    expect(documents, isEmpty);
  });

  test(
    'uses search_text for embeddings and the full record for answers',
    () async {
      final source = JsonDocumentSource(
        assetBundle: _StringAssetBundle(
          jsonEncode({
            'metadata': {'source': 'Service manual'},
            'entries': [
              {
                'id': 'passage:p1',
                'type': 'passage',
                'title': 'Service instructions',
                'text': 'Isolate power before servicing.',
                'pages': [1],
              },
              {
                'id': 'card:msg:f_74',
                'type': 'card',
                'entity_type': 'message',
                'title': 'FAULT F.74',
                'text': 'Code: F.74\nCause: Pressure too low',
                'search_text': 'F.74 low pressure',
                'phrasings': ['Pressure keeps dropping after refill'],
                'source_passage_ids': ['passage:p1'],
                'pages': [74],
                'measures': [
                  {'text': 'Refill the system'},
                ],
                'fix_procedures': [
                  {'id': 'card:proc:refill'},
                ],
              },
            ],
          }),
        ),
      );

      final documents = await source.loadDocuments();

      expect(documents, hasLength(2));
      expect(documents.last.metadata['code'], 'F.74');
      expect(documents.last.metadata['pages'], [74]);
      expect(documents.last.metadata['source_passage_ids'], ['passage:p1']);
      expect(documents.last.searchText, 'F.74 low pressure');
      final storedRecord = jsonDecode(documents.last.content);
      expect(storedRecord['phrasings'], [
        'Pressure keeps dropping after refill',
      ]);
      expect(storedRecord['measures'], [
        {'text': 'Refill the system'},
      ]);
      expect(storedRecord['fix_procedures'], [
        {'id': 'card:proc:refill'},
      ]);
      expect(documents.first.searchText, isNull);
      expect(
        jsonDecode(documents.first.content)['text'],
        'Isolate power before servicing.',
      );
    },
  );

  test('indexes unknown JSON records with stable asset-scoped IDs', () async {
    final source = JsonDocumentSource(
      assetPath: 'assets/knowledge_base/new.json',
      assetBundle: _StringAssetBundle(
        jsonEncode({
          'release': '2026',
          'faults': [
            {
              'name': 'Low pressure',
              'details': {'cause': 'Water loss'},
              'steps': ['Fill', 'Vent'],
            },
          ],
          'parts': [
            {'code': 'X123', 'description': 'Temperature probe'},
          ],
        }),
      ),
    );

    final documents = await source.loadDocuments();

    expect(documents.map((document) => document.id), [
      'assets/knowledge_base/new.json#faults/0',
      'assets/knowledge_base/new.json#parts/0',
    ]);
    expect(documents.first.title, 'Low pressure');
    expect(documents.first.content, contains('Water loss'));
    expect(documents.first.content, contains('Vent'));
    expect(jsonDecode(documents.first.content)['steps'], ['Fill', 'Vent']);
    expect(documents.first.searchText, isNull);
    expect(documents.last.metadata['code'], 'X123');
  });

  test('rejects non-object records instead of silently skipping them', () {
    final source = JsonDocumentSource(
      assetBundle: _StringAssetBundle(
        jsonEncode([
          {'name': 'Valid', 'description': 'Text'},
          4,
        ]),
      ),
    );
    expect(source.loadDocuments, throwsFormatException);
  });

  test('supports other versioned JSON schemas', () async {
    final source = JsonDocumentSource(
      assetBundle: _StringAssetBundle(
        jsonEncode({
          'version': 2,
          'articles': [
            {'title': 'Circulation', 'detail': 'Check the pump.'},
          ],
        }),
      ),
    );

    expect(
      (await source.loadDocuments()).single.content,
      contains('Check the pump.'),
    );
  });

  test('legacy documents use explicit search_text when provided', () async {
    final record = {..._document(), 'search_text': 'network help'};
    final source = JsonDocumentSource(
      assetBundle: _StringAssetBundle(
        jsonEncode({
          'version': 1,
          'documents': [record],
        }),
      ),
    );

    final document = (await source.loadDocuments()).single;
    expect(document.searchText, 'network help');
    expect(jsonDecode(document.content), record);
  });
}

class _StringAssetBundle extends CachingAssetBundle {
  _StringAssetBundle(this._content);

  final String _content;

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(_content));
    return ByteData.sublistView(bytes);
  }
}

String _knowledgeBaseJson() {
  return jsonEncode({
    'version': 1,
    'documents': [
      _document(measures: 'Check that the device has network access.'),
      _document(id: 'error-e456', code: 'E456'),
    ],
  });
}

Map<String, Object?> _document({
  String id = 'error-e123',
  String code = 'E123',
  String? measures,
}) {
  return {
    'id': id,
    'title': 'Device cannot connect to network',
    'content': 'The device cannot establish a network connection.',
    'measures': measures,
    'metadata': {'type': 'error', 'code': code},
  };
}
