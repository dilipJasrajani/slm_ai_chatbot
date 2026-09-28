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
