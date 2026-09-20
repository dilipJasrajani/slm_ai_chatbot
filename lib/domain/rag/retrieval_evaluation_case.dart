class RetrievalEvaluationCase {
  const RetrievalEvaluationCase({
    required this.id,
    required this.query,
    required this.expectedDocumentIds,
    this.topK,
  });

  final String id;
  final String query;
  final List<String> expectedDocumentIds;
  final int? topK;
}
