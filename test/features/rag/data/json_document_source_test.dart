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
    expect(documents.last.metadata['code'], 'E456');
    expect(documents.last.metadata['type'], 'error');
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

  testWidgets('loads the bundled documents asset', (tester) async {
    final source = JsonDocumentSource(assetBundle: rootBundle);

    final documents = await source.loadDocuments();

    expect(documents, hasLength(3));
    expect(documents.first.id, 'error-e123');
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
    'documents': [_document(), _document(id: 'error-e456', code: 'E456')],
  });
}

Map<String, Object> _document({
  String id = 'error-e123',
  String code = 'E123',
}) {
  return {
    'id': id,
    'title': 'Device cannot connect to network',
    'content': 'The device cannot establish a network connection.',
    'metadata': {'type': 'error', 'code': code},
  };
}
