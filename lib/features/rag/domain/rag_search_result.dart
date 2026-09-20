import 'knowledge_document.dart';

/// A retrieved document and the similarity supplied by the vector search.
class RagSearchResult {
  const RagSearchResult({required this.document, required this.similarity});

  final KnowledgeDocument document;
  final double similarity;
}
