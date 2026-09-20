import 'evaluate_retrieval_use_case.dart';
import 'ingest_documents_use_case.dart';
import 'retrieval_evaluation_dataset_source.dart';
import 'retrieval_evaluation_result.dart';

class RetrievalEvaluationRunner {
  RetrievalEvaluationRunner({
    required IngestDocumentsUseCase ingestDocuments,
    required RetrievalEvaluationDatasetSource datasetSource,
    required EvaluateRetrievalUseCase evaluateRetrieval,
  }) : _ingestDocuments = ingestDocuments,
       _datasetSource = datasetSource,
       _evaluateRetrieval = evaluateRetrieval;

  final IngestDocumentsUseCase _ingestDocuments;
  final RetrievalEvaluationDatasetSource _datasetSource;
  final EvaluateRetrievalUseCase _evaluateRetrieval;

  Future<RetrievalEvaluationSummary> run({
    int topK = 3,
    void Function(DocumentIngestionProgress progress)? onIngestionProgress,
  }) async {
    await _ingestDocuments(onProgress: onIngestionProgress);
    final dataset = await _datasetSource.loadDataset();
    return _evaluateRetrieval(dataset.cases, topK: topK);
  }
}
