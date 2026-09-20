import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/domain/document_source.dart';
import 'package:slm_ai_chatbot/features/rag/domain/ingest_documents_use_case.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_search_result.dart';

void main() {
  test(
    'loads and indexes every document with deterministic searchable text',
    () async {
      final ragRepository = _FakeRagRepository();
      final progress = <DocumentIngestionStage>[];
      final useCase = IngestDocumentsUseCase(
        documentSource: _FakeDocumentSource([
          _knowledgeDocument('error-e123', 'E123'),
          _knowledgeDocument('error-e456', 'E456'),
        ]),
        ragRepository: ragRepository,
      );

      final result = await useCase(
        onProgress: (update) => progress.add(update.stage),
      );

      expect(result.documentCount, 2);
      expect(progress, [
        DocumentIngestionStage.loading,
        DocumentIngestionStage.loaded,
        DocumentIngestionStage.indexing,
        DocumentIngestionStage.ready,
      ]);
      expect(ragRepository.indexed.map((document) => document.document.id), [
        'error-e123',
        'error-e456',
      ]);
      expect(
        ragRepository.indexed.first.searchableText,
        contains('code: E123'),
      );
      expect(
        ragRepository.indexed.first.searchableText,
        contains('Content:\nThe device cannot connect to the network.'),
      );
    },
  );
}

KnowledgeDocument _knowledgeDocument(String id, String code) {
  return KnowledgeDocument(
    id: id,
    title: 'Network connection failed',
    content: 'The device cannot connect to the network.',
    metadata: {'type': 'error', 'code': code},
  );
}

class _FakeDocumentSource implements DocumentSource {
  const _FakeDocumentSource(this.documents);

  final List<KnowledgeDocument> documents;

  @override
  Future<List<KnowledgeDocument>> loadDocuments() async => documents;
}

class _FakeRagRepository implements RagRepository {
  final indexed = <RagDocument>[];

  @override
  Future<void> indexDocuments(Iterable<RagDocument> documents) async {
    indexed.addAll(documents);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<List<RagSearchResult>> search({
    required String query,
    int topK = 1,
    double threshold = 0.0,
  }) async {
    return const [];
  }
}
