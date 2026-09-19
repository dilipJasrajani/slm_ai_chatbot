import 'knowledge_document.dart';

class RagDocument {
  const RagDocument({required this.document, required this.searchableText});

  final KnowledgeDocument document;
  final String searchableText;
}
