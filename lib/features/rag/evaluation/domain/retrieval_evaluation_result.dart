enum RetrievalEvaluationStatus { passed, failed, noKnownMatch }

class RetrievalEvaluationRetrievedDocument {
  const RetrievalEvaluationRetrievedDocument({
    required this.documentId,
    required this.similarity,
  });

  final String documentId;
  final double similarity;
}

class RetrievalEvaluationResult {
  const RetrievalEvaluationResult({
    required this.caseId,
    required this.query,
    required this.expectedDocumentIds,
    required this.retrievedDocuments,
    required this.matchedDocumentIds,
    required this.status,
  });

  final String caseId;
  final String query;
  final List<String> expectedDocumentIds;
  final List<RetrievalEvaluationRetrievedDocument> retrievedDocuments;
  final List<String> matchedDocumentIds;
  final RetrievalEvaluationStatus status;

  List<String> get retrievedDocumentIds => retrievedDocuments
      .map((document) => document.documentId)
      .toList(growable: false);

  bool get passed => status == RetrievalEvaluationStatus.passed;
}

class RetrievalEvaluationSummary {
  const RetrievalEvaluationSummary({
    required this.results,
    required this.hitRateAt1,
    required this.hitRateAt3,
  });

  final List<RetrievalEvaluationResult> results;
  final double hitRateAt1;
  final double hitRateAt3;

  int get totalCases => results.length;
  int get expectedMatchCaseCount =>
      results.where((result) => result.expectedDocumentIds.isNotEmpty).length;
  int get passedCaseCount => results.where((result) => result.passed).length;
  int get failedCaseCount => results
      .where((result) => result.status == RetrievalEvaluationStatus.failed)
      .length;
  int get noKnownMatchCaseCount => results
      .where(
        (result) => result.status == RetrievalEvaluationStatus.noKnownMatch,
      )
      .length;
}
