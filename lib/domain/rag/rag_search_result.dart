import 'knowledge_document.dart';

class RagSearchResult {
  const RagSearchResult({required this.document, required this.similarity});

  final KnowledgeDocument document;
  final double similarity;
}
