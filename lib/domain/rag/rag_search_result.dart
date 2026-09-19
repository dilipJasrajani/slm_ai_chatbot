class RagSearchResult {
  const RagSearchResult({
    required this.id,
    required this.content,
    required this.similarity,
    this.metadata,
  });

  final String id;
  final String content;
  final double similarity;
  final Map<String, String>? metadata;
}
