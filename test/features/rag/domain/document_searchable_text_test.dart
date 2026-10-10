import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/domain/document_searchable_text.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';

void main() {
  test('uses the complete serialized record when search text is absent', () {
    const document = KnowledgeDocument(
      id: 'error-e123',
      title: 'Device cannot connect to network',
      content: '{"id":"error-e123","steps":["Check network","Retry"]}',
      metadata: {'type': 'error', 'code': 'E123'},
    );

    expect(const DocumentSearchableText().format(document), document.content);
  });

  test('uses only search_text when it is present', () {
    const document = KnowledgeDocument(
      id: 'error-e123',
      title: 'Device cannot connect to network',
      content: '{"id":"error-e123","measures":["Check Wi-Fi"]}',
      searchText: 'Network connection troubleshooting',
      metadata: {'type': 'error', 'code': 'E123'},
    );

    expect(
      const DocumentSearchableText().format(document),
      'Network connection troubleshooting',
    );
  });
}
