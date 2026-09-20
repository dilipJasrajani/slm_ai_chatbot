import 'chat_route.dart';

enum ChatIntentEvaluationStatus { passed, failed }

class ChatIntentEvaluationResult {
  const ChatIntentEvaluationResult({
    required this.caseId,
    required this.message,
    required this.expectedRoute,
    required this.actualRoute,
    required this.latency,
    required this.status,
  });

  final String caseId;
  final String message;
  final ChatRoute expectedRoute;
  final ChatRoute actualRoute;
  final Duration latency;
  final ChatIntentEvaluationStatus status;

  bool get passed => status == ChatIntentEvaluationStatus.passed;
}

class ChatIntentEvaluationSummary {
  const ChatIntentEvaluationSummary({
    required this.results,
    required this.accuracy,
    required this.averageLatency,
    required this.maxLatency,
  });

  final List<ChatIntentEvaluationResult> results;
  final double accuracy;
  final Duration averageLatency;
  final Duration maxLatency;

  int get totalCases => results.length;
  int get passedCaseCount => results.where((result) => result.passed).length;
  int get failedCaseCount => totalCases - passedCaseCount;
}
