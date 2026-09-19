import 'knowledge_document.dart';

abstract class DocumentSource {
  Future<List<KnowledgeDocument>> loadDocuments();
}
