import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/domain/rag/evaluate_retrieval_use_case.dart';
import 'package:slm_ai_chatbot/domain/rag/knowledge_document.dart';
import 'package:slm_ai_chatbot/domain/rag/rag_document.dart';
import 'package:slm_ai_chatbot/domain/rag/rag_repository.dart';
import 'package:slm_ai_chatbot/domain/rag/rag_search_result.dart';
import 'package:slm_ai_chatbot/domain/rag/retrieval_evaluation_case.dart';
import 'package:slm_ai_chatbot/domain/rag/retrieval_evaluation_result.dart';

void main() {
  test(
    'passes when an expected document is retrieved in the configured top K',
    () async {
      final repository = _FakeRagRepository({
        'network': [
          _result('error-e456'),
          _result('error-e123'),
          _result('error-e789'),
        ],
      });
      final useCase = EvaluateRetrievalUseCase(ragRepository: repository);

      final summary = await useCase([
        const RetrievalEvaluationCase(
          id: 'network',
          query: 'network',
          expectedDocumentIds: ['error-e123'],
        ),
      ]);

      final result = summary.results.single;
      expect(repository.topKs, [3]);
      expect(result.status, RetrievalEvaluationStatus.passed);
      expect(result.matchedDocumentIds, ['error-e123']);
      expect(result.retrievedDocumentIds, [
        'error-e456',
        'error-e123',
        'error-e789',
      ]);
      expect(result.retrievedDocuments[1].similarity, 0.8);
    },
  );

  test('fails when an expected document is not retrieved', () async {
    final useCase = EvaluateRetrievalUseCase(
      ragRepository: _FakeRagRepository({
        'network': [_result('error-e456'), _result('error-e789')],
      }),
    );

    final summary = await useCase([
      const RetrievalEvaluationCase(
        id: 'network',
        query: 'network',
        expectedDocumentIds: ['error-e123'],
      ),
    ]);

    expect(summary.results.single.status, RetrievalEvaluationStatus.failed);
  });

  test('classifies unrelated queries as no known match', () async {
    final useCase = EvaluateRetrievalUseCase(
      ragRepository: _FakeRagRepository({
        'unrelated': [_result('error-e123')],
      }),
    );

    final summary = await useCase([
      const RetrievalEvaluationCase(
        id: 'unrelated',
        query: 'unrelated',
        expectedDocumentIds: [],
      ),
    ]);

    expect(
      summary.results.single.status,
      RetrievalEvaluationStatus.noKnownMatch,
    );
    expect(summary.noKnownMatchCaseCount, 1);
  });

  test(
    'calculates Hit Rate at 1 and 3 without counting unrelated cases',
    () async {
      final useCase = EvaluateRetrievalUseCase(
        ragRepository: _FakeRagRepository({
          'first': [_result('error-e123'), _result('error-e456')],
          'third': [
            _result('error-e456'),
            _result('error-e789'),
            _result('error-e123'),
          ],
          'failed': [_result('error-e456'), _result('error-e789')],
          'unrelated': [_result('error-e123')],
        }),
      );

      final summary = await useCase([
        const RetrievalEvaluationCase(
          id: 'first',
          query: 'first',
          expectedDocumentIds: ['error-e123'],
        ),
        const RetrievalEvaluationCase(
          id: 'third',
          query: 'third',
          expectedDocumentIds: ['error-e123'],
        ),
        const RetrievalEvaluationCase(
          id: 'failed',
          query: 'failed',
          expectedDocumentIds: ['error-e123'],
        ),
        const RetrievalEvaluationCase(
          id: 'unrelated',
          query: 'unrelated',
          expectedDocumentIds: [],
        ),
      ]);

      expect(summary.totalCases, 4);
      expect(summary.expectedMatchCaseCount, 3);
      expect(summary.passedCaseCount, 2);
      expect(summary.failedCaseCount, 1);
      expect(summary.noKnownMatchCaseCount, 1);
      expect(summary.hitRateAt1, closeTo(1 / 3, 0.0001));
      expect(summary.hitRateAt3, closeTo(2 / 3, 0.0001));
    },
  );

  test('returns zero hit rates for zero cases', () async {
    final summary = await EvaluateRetrievalUseCase(
      ragRepository: _FakeRagRepository(const {}),
    )(const []);

    expect(summary.totalCases, 0);
    expect(summary.hitRateAt1, 0);
    expect(summary.hitRateAt3, 0);
  });
}

RagSearchResult _result(String id) {
  return RagSearchResult(
    document: KnowledgeDocument(
      id: id,
      title: id,
      content: id,
      metadata: const {},
    ),
    similarity: id == 'error-e123' ? 0.8 : 0.6,
  );
}

class _FakeRagRepository implements RagRepository {
  _FakeRagRepository(this.responses);

  final Map<String, List<RagSearchResult>> responses;
  final topKs = <int>[];

  @override
  Future<void> indexDocuments(Iterable<RagDocument> documents) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<List<RagSearchResult>> search({
    required String query,
    int topK = 1,
    double threshold = 0.0,
  }) async {
    topKs.add(topK);
    return responses[query] ?? const [];
  }
}
