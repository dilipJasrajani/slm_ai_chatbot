import 'document_searchable_text.dart';
import 'document_source.dart';
import 'rag_document.dart';
import 'rag_repository.dart';

enum DocumentIngestionStage { loading, loaded, indexing, ready }

class DocumentIngestionProgress {
  const DocumentIngestionProgress({
    required this.stage,
    required this.documentCount,
  });

  final DocumentIngestionStage stage;
  final int documentCount;
}

class DocumentIngestionResult {
  const DocumentIngestionResult({required this.documentCount});

  final int documentCount;
}

/// Loads source documents, creates searchable text, and indexes them for RAG.
class IngestDocumentsUseCase {
  IngestDocumentsUseCase({
    required DocumentSource documentSource,
    required RagRepository ragRepository,
    DocumentSearchableText searchableText = const DocumentSearchableText(),
  }) : _documentSource = documentSource,
       _ragRepository = ragRepository,
       _searchableText = searchableText;

  final DocumentSource _documentSource;
  final RagRepository _ragRepository;
  final DocumentSearchableText _searchableText;

  Future<DocumentIngestionResult> call({
    void Function(DocumentIngestionProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const DocumentIngestionProgress(
        stage: DocumentIngestionStage.loading,
        documentCount: 0,
      ),
    );
    final documents = await _documentSource.loadDocuments();
    onProgress?.call(
      DocumentIngestionProgress(
        stage: DocumentIngestionStage.loaded,
        documentCount: documents.length,
      ),
    );

    onProgress?.call(
      DocumentIngestionProgress(
        stage: DocumentIngestionStage.indexing,
        documentCount: documents.length,
      ),
    );
    await _ragRepository.indexDocuments(
      documents
          .map(
            (document) => RagDocument(
              document: document,
              searchableText: _searchableText.format(document),
            ),
          )
          .toList(growable: false),
    );

    onProgress?.call(
      DocumentIngestionProgress(
        stage: DocumentIngestionStage.ready,
        documentCount: documents.length,
      ),
    );
    return DocumentIngestionResult(documentCount: documents.length);
  }
}
