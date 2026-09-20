/// Source knowledge retained with its stable identity and descriptive fields.
class KnowledgeDocument {
  const KnowledgeDocument({
    required this.id,
    required this.title,
    required this.content,
    required this.metadata,
  });

  final String id;
  final String title;
  final String content;
  final Map<String, dynamic> metadata;
}
