/// Source knowledge retained with its stable identity and descriptive fields.
class KnowledgeDocument {
  const KnowledgeDocument({
    required this.id,
    required this.title,
    required this.content,
    this.measures,
    this.searchText,
    required this.metadata,
  });

  final String id;
  final String title;
  final String content;
  final String? measures;
  final String? searchText;
  final Map<String, dynamic> metadata;
}
