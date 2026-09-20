import 'retrieval_evaluation_dataset.dart';

abstract class RetrievalEvaluationDatasetSource {
  Future<RetrievalEvaluationDataset> loadDataset();
}
