import 'chat_intent_evaluation_case.dart';
import 'chat_intent_evaluation_result.dart';
import 'chat_intent_router.dart';

class EvaluateChatIntentRoutingUseCase {
  EvaluateChatIntentRoutingUseCase({required ChatIntentRouter router})
    : _router = router;

  final ChatIntentRouter _router;

  Future<ChatIntentEvaluationSummary> call(
    Iterable<ChatIntentEvaluationCase> cases,
  ) async {
    final results = <ChatIntentEvaluationResult>[];
    for (final evaluationCase in cases) {
      results.add(await _evaluateCase(evaluationCase));
    }

    return ChatIntentEvaluationSummary(
      results: List.unmodifiable(results),
      accuracy: _accuracy(results),
      averageLatency: _averageLatency(results),
      maxLatency: _maxLatency(results),
    );
  }

  Future<ChatIntentEvaluationResult> _evaluateCase(
    ChatIntentEvaluationCase evaluationCase,
  ) async {
    final stopwatch = Stopwatch()..start();
    final actualRoute = await _router.route(evaluationCase.message);
    stopwatch.stop();

    return ChatIntentEvaluationResult(
      caseId: evaluationCase.id,
      message: evaluationCase.message,
      expectedRoute: evaluationCase.expectedRoute,
      actualRoute: actualRoute,
      latency: stopwatch.elapsed,
      status: actualRoute == evaluationCase.expectedRoute
          ? ChatIntentEvaluationStatus.passed
          : ChatIntentEvaluationStatus.failed,
    );
  }

  double _accuracy(List<ChatIntentEvaluationResult> results) {
    if (results.isEmpty) return 0;
    return results.where((result) => result.passed).length / results.length;
  }

  Duration _averageLatency(List<ChatIntentEvaluationResult> results) {
    if (results.isEmpty) return Duration.zero;
    final totalMicroseconds = results.fold<int>(
      0,
      (total, result) => total + result.latency.inMicroseconds,
    );
    return Duration(microseconds: totalMicroseconds ~/ results.length);
  }

  Duration _maxLatency(List<ChatIntentEvaluationResult> results) {
    if (results.isEmpty) return Duration.zero;
    return results
        .map((result) => result.latency)
        .reduce((left, right) => left >= right ? left : right);
  }
}
