import 'chat_intent_evaluation_dataset_source.dart';
import 'chat_intent_evaluation_result.dart';
import 'evaluate_chat_intent_routing_use_case.dart';

class ChatIntentEvaluationRunner {
  ChatIntentEvaluationRunner({
    required ChatIntentEvaluationDatasetSource datasetSource,
    required EvaluateChatIntentRoutingUseCase evaluateRouting,
  }) : _datasetSource = datasetSource,
       _evaluateRouting = evaluateRouting;

  final ChatIntentEvaluationDatasetSource _datasetSource;
  final EvaluateChatIntentRoutingUseCase _evaluateRouting;

  Future<ChatIntentEvaluationSummary> run() async {
    final dataset = await _datasetSource.loadDataset();
    return _evaluateRouting(dataset.cases);
  }
}
