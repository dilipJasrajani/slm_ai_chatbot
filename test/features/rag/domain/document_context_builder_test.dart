import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/domain/document_context_builder.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';

void main() {
  test('builds deterministic context from multiple generic documents', () {
    const documents = [
      KnowledgeDocument(
        id: 'network-guide',
        title: 'Network guide',
        content: 'Check that Wi-Fi is enabled.',
        metadata: {'type': 'guide', 'priority': 1},
      ),
      KnowledgeDocument(
        id: 'faq-1',
        title: 'Connection FAQ',
        content: 'Retry the connection.',
        metadata: {'type': 'faq'},
      ),
    ];

    final context = const DocumentContextBuilder().build(documents);

    expect(context, contains('Knowledge Document 1'));
    expect(context, contains('Title:\nNetwork guide'));
    expect(context, contains('Content:\nCheck that Wi-Fi is enabled.'));
    expect(context, contains('priority: 1\ntype: guide'));
    expect(context, contains('Knowledge Document 2'));
    expect(const DocumentContextBuilder().build(documents), context);
  });

  test('returns empty context for no documents', () {
    expect(const DocumentContextBuilder().build(const []), isEmpty);
  });
}
