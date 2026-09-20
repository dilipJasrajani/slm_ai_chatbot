import 'knowledge_document.dart';

/// Loads source knowledge into the generic document model.
abstract class DocumentSource {
  Future<List<KnowledgeDocument>> loadDocuments();
}
