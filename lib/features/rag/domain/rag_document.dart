import 'knowledge_document.dart';

/// Pairs source knowledge with the text used for embedding and vector search.
class RagDocument {
  const RagDocument({required this.document, required this.searchableText});

  final KnowledgeDocument document;
  final String searchableText;
}
