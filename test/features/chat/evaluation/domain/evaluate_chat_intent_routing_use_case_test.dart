import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_intent_router.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_route.dart';
import 'package:slm_ai_chatbot/features/chat/evaluation/domain/chat_intent_evaluation_case.dart';
import 'package:slm_ai_chatbot/features/chat/evaluation/domain/evaluate_chat_intent_routing_use_case.dart';

void main() {
  test('calculates accuracy and latency metrics', () async {
    final useCase = EvaluateChatIntentRoutingUseCase(
      router: _QueueRouter([
        ChatRoute.chat,
        ChatRoute.knowledge,
        ChatRoute.chat,
      ]),
    );

    final summary = await useCase([
      const ChatIntentEvaluationCase(
        id: 'greeting',
        message: 'Hi',
        expectedRoute: ChatRoute.chat,
      ),
      const ChatIntentEvaluationCase(
        id: 'knowledge',
        message: 'What does E123 mean?',
        expectedRoute: ChatRoute.knowledge,
      ),
      const ChatIntentEvaluationCase(
        id: 'mismatch',
        message: 'Thanks',
        expectedRoute: ChatRoute.knowledge,
      ),
    ]);

    expect(summary.totalCases, 3);
    expect(summary.passedCaseCount, 2);
    expect(summary.failedCaseCount, 1);
    expect(summary.accuracy, closeTo(2 / 3, 0.0001));
    expect(summary.averageLatency, greaterThanOrEqualTo(Duration.zero));
    expect(summary.maxLatency, greaterThanOrEqualTo(Duration.zero));
    expect(summary.results.first.latency, greaterThanOrEqualTo(Duration.zero));
    expect(summary.maxLatency, greaterThanOrEqualTo(summary.averageLatency));
    expect(summary.results.last.actualRoute, ChatRoute.chat);
  });

  test('returns zeroed metrics for an empty dataset', () async {
    final summary = await EvaluateChatIntentRoutingUseCase(
      router: _QueueRouter(const []),
    )(const []);

    expect(summary.totalCases, 0);
    expect(summary.accuracy, 0);
    expect(summary.averageLatency, Duration.zero);
    expect(summary.maxLatency, Duration.zero);
  });
}

class _QueueRouter implements ChatIntentRouter {
  _QueueRouter(this._routes);

  final List<ChatRoute> _routes;
  var _index = 0;

  @override
  Future<ChatRoute> route(String message) async => _routes[_index++];
}
