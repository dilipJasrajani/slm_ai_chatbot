class RagDocument {
  const RagDocument({required this.id, required this.content, this.metadata});

  final String id;
  final String content;
  final Map<String, String>? metadata;
}
