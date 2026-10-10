import 'knowledge_document.dart';

/// Chooses the text used for embedding, independent of stored answer content.
class DocumentSearchableText {
  const DocumentSearchableText();

  String format(KnowledgeDocument document) {
    return document.searchText ?? document.content;
  }
}
