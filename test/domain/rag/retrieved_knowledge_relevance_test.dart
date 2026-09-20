import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/domain/rag/knowledge_document.dart';
import 'package:slm_ai_chatbot/domain/rag/rag_search_result.dart';
import 'package:slm_ai_chatbot/domain/rag/retrieved_knowledge_relevance.dart';

void main() {
  const relevance = RetrievedKnowledgeRelevance();
  const documents = [
    KnowledgeDocument(
      id: 'error-e123',
      title: 'Device cannot connect to network',
      content: 'Check Wi-Fi credentials and network range.',
      metadata: {'type': 'error', 'code': 'E123'},
    ),
    KnowledgeDocument(
      id: 'error-e456',
      title: 'Authentication failed',
      content: 'Verify credentials and sign in again.',
      metadata: {'type': 'error', 'code': 'E456'},
    ),
    KnowledgeDocument(
      id: 'error-e789',
      title: 'Device communication timeout',
      content: 'Check device connectivity and retry the operation.',
      metadata: {'type': 'error', 'code': 'E789'},
    ),
  ];
  final results = documents
      .map((document) => RagSearchResult(document: document, similarity: 0.5))
      .toList(growable: false);

  test('keeps knowledge documents supported by question terms', () {
    final cases = {
      'E123': 'error-e123',
      "My device can't connect to Wi-Fi.": 'error-e123',
      'Why did authentication fail?': 'error-e456',
      'The device is timing out while communicating.': 'error-e789',
    };

    for (final entry in cases.entries) {
      final documents = relevance.relevantDocuments(
        question: entry.key,
        results: results,
      );

      expect(documents.map((document) => document.id), contains(entry.value));
    }
  });

  test('rejects nearest documents without lexical grounding evidence', () {
    for (final question in [
      'What is the capital of France?',
      'Tell me a joke.',
      'What is the weather today?',
      'Write me a poem.',
    ]) {
      expect(
        relevance.relevantDocuments(question: question, results: results),
        isEmpty,
      );
    }
  });
}
