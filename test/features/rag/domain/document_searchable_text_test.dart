import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/domain/document_searchable_text.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';

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

  test('includes measures in vector-search text when present', () {
    const document = KnowledgeDocument(
      id: 'error-e123',
      title: 'Device cannot connect to network',
      content: 'The device is unable to establish a network connection.',
      measures: 'Check that Wi-Fi is enabled.',
      metadata: {'type': 'error', 'code': 'E123'},
    );

    final text = const DocumentSearchableText().format(document);

    expect(
      text,
      contains(
        'Content:\nThe device is unable to establish a network connection.'
        '\n\nMeasures:\nCheck that Wi-Fi is enabled.'
        '\n\nMetadata:\ncode: E123\ntype: error',
      ),
    );
  });

  test(
    'prioritizes retrieval phrasings without adding them to factual content',
    () {
      const document = KnowledgeDocument(
        id: 'card:msg:f_74',
        title: 'FAULT F.74',
        content: 'Cause: Hydraulic pressure too low.',
        searchText: 'Pressure drops after refill',
        metadata: {'code': 'F.74'},
      );

      final text = const DocumentSearchableText().format(document);
      expect(text.indexOf('Pressure drops'), lessThan(text.indexOf('Cause:')));
      expect(document.content, isNot(contains('Pressure drops')));
    },
  );
}
