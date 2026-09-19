import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/domain/rag/document_searchable_text.dart';
import 'package:slm_ai_chatbot/domain/rag/knowledge_document.dart';

void main() {
  test('includes generic document fields and metadata deterministically', () {
    const document = KnowledgeDocument(
      id: 'error-e123',
      title: 'Device cannot connect to network',
      content: 'The device is unable to establish a network connection.',
      metadata: {'type': 'error', 'code': 'E123'},
    );

    final formatter = const DocumentSearchableText();
    final text = formatter.format(document);

    expect(text, contains('Title: Device cannot connect to network'));
    expect(text, contains(document.content));
    expect(text, contains('Metadata:\ncode: E123\ntype: error'));
    expect(formatter.format(document), text);
  });
}
