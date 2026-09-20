import 'rag_repository.dart';
import 'retrieval_evaluation_case.dart';
import 'retrieval_evaluation_result.dart';

class EvaluateRetrievalUseCase {
  EvaluateRetrievalUseCase({required RagRepository ragRepository})
    : _ragRepository = ragRepository;

  final RagRepository _ragRepository;

  Future<RetrievalEvaluationSummary> call(
    Iterable<RetrievalEvaluationCase> cases, {
    int topK = 3,
  }) async {
    if (topK < 1) {
      throw ArgumentError.value(topK, 'topK', 'Must be at least 1.');
    }

    final results = <RetrievalEvaluationResult>[];
    for (final evaluationCase in cases) {
      results.add(
        await _evaluateCase(evaluationCase, topK: evaluationCase.topK ?? topK),
      );
    }
    return RetrievalEvaluationSummary(
      results: List.unmodifiable(results),
      hitRateAt1: _hitRateAt(results, 1),
      hitRateAt3: _hitRateAt(results, 3),
    );
  }

  Future<RetrievalEvaluationResult> _evaluateCase(
    RetrievalEvaluationCase evaluationCase, {
    required int topK,
  }) async {
    if (topK < 1) {
      throw ArgumentError.value(
        topK,
        'topK',
        'Case "${evaluationCase.id}" must use at least 1.',
      );
    }

    final searchResults = await _ragRepository.search(
      query: evaluationCase.query,
      topK: topK,
    );
    final expectedIds = evaluationCase.expectedDocumentIds.toSet();
    final retrievedDocuments = searchResults
        .map(
          (result) => RetrievalEvaluationRetrievedDocument(
            documentId: result.document.id,
            similarity: result.similarity,
          ),
        )
        .toList(growable: false);
    final matchedIds = retrievedDocuments
        .map((document) => document.documentId)
        .where(expectedIds.contains)
        .toList(growable: false);

    return RetrievalEvaluationResult(
      caseId: evaluationCase.id,
      query: evaluationCase.query,
      expectedDocumentIds: List.unmodifiable(
        evaluationCase.expectedDocumentIds,
      ),
      retrievedDocuments: retrievedDocuments,
      matchedDocumentIds: matchedIds,
      status: expectedIds.isEmpty
          ? RetrievalEvaluationStatus.noKnownMatch
          : matchedIds.isNotEmpty
          ? RetrievalEvaluationStatus.passed
          : RetrievalEvaluationStatus.failed,
    );
  }

  double _hitRateAt(List<RetrievalEvaluationResult> results, int rank) {
    final expectedMatchResults = results
        .where((result) => result.expectedDocumentIds.isNotEmpty)
        .toList(growable: false);
    if (expectedMatchResults.isEmpty) {
      return 0;
    }

    final hitCount = expectedMatchResults.where((result) {
      final expectedIds = result.expectedDocumentIds.toSet();
      return result.retrievedDocuments
          .take(rank)
          .any((document) => expectedIds.contains(document.documentId));
    }).length;
    return hitCount / expectedMatchResults.length;
  }
}
