import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/chat/data/local_llm_chat_intent_router.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_intent_router.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_route.dart';
import 'package:slm_ai_chatbot/features/llm/domain/local_llm_service.dart';

void main() {
  test('collects streamed output before parsing the route', () async {
    final llmService = _FakeLlmService(
      () => Stream<String>.fromIterable(['  ch', 'at \n']),
    );
    final router = LocalLlmChatIntentRouter(llmService: llmService);

    final route = await router.route('Hi there');

    expect(route, ChatRoute.chat);
    expect(llmService.prompt, contains('Hi there'));
  });

  test('accepts a clear label with an explanatory suffix', () async {
    final router = LocalLlmChatIntentRouter(
      llmService: _FakeLlmService(() => Stream.value('CHAT because casual')),
      fallbackRouter: const _FixedRouter(ChatRoute.chat),
    );

    final route = await router.route('Tell me something nice');

    expect(route, ChatRoute.chat);
  });

  test(
    'uses the optional fallback router when routing generation fails',
    () async {
      final router = LocalLlmChatIntentRouter(
        llmService: _FakeLlmService(
          () => Stream<String>.error(Exception('routing failed')),
        ),
        fallbackRouter: const _FixedRouter(ChatRoute.chat),
      );

      final route = await router.route('Thanks');

      expect(route, ChatRoute.chat);
    },
  );
}

class _FakeLlmService implements LocalLlmService {
  _FakeLlmService(this._responses);

  final Stream<String> Function() _responses;
  String? prompt;

  @override
  Future<void> dispose() async {}

  @override
  Stream<String> generate(String prompt) {
    this.prompt = prompt;
    return _responses();
  }

  @override
  Future<void> stop() async {}
}

class _FixedRouter implements ChatIntentRouter {
  const _FixedRouter(this.routeValue);

  final ChatRoute routeValue;

  @override
  Future<ChatRoute> route(String message) async => routeValue;
}
