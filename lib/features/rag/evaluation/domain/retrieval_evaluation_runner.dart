import 'evaluate_retrieval_use_case.dart';
import '../../domain/ingest_documents_use_case.dart';
import 'retrieval_evaluation_dataset_source.dart';
import 'retrieval_evaluation_result.dart';

class RetrievalEvaluationRunner {
  RetrievalEvaluationRunner({
    required Future<void> Function({
      void Function(DocumentIngestionProgress progress)? onProgress,
    })
    prepareIndex,
    required RetrievalEvaluationDatasetSource datasetSource,
    required EvaluateRetrievalUseCase evaluateRetrieval,
  }) : _prepareIndex = prepareIndex,
       _datasetSource = datasetSource,
       _evaluateRetrieval = evaluateRetrieval;

  final Future<void> Function({
    void Function(DocumentIngestionProgress progress)? onProgress,
  })
  _prepareIndex;
  final RetrievalEvaluationDatasetSource _datasetSource;
  final EvaluateRetrievalUseCase _evaluateRetrieval;

  Future<RetrievalEvaluationSummary> run({
    int topK = 3,
    void Function(DocumentIngestionProgress progress)? onIngestionProgress,
  }) async {
    await _prepareIndex(onProgress: onIngestionProgress);
    final dataset = await _datasetSource.loadDataset();
    return _evaluateRetrieval(dataset.cases, topK: topK);
  }
}
