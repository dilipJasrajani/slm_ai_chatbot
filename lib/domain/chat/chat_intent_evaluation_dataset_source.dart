import 'chat_intent_evaluation_dataset.dart';

abstract interface class ChatIntentEvaluationDatasetSource {
  Future<ChatIntentEvaluationDataset> loadDataset();
}
