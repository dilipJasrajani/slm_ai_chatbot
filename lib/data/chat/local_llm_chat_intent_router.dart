import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../../domain/chat/chat_intent_router.dart';
import '../../domain/chat/chat_intent_routing_prompt_builder.dart';
import '../../domain/chat/chat_route.dart';
import '../../domain/chat/chat_route_parser.dart';
import '../../domain/chat/conversation_message.dart';
import '../../domain/llm/local_llm_service.dart';

class LocalLlmChatIntentRouter implements HistoryAwareChatIntentRouter {
  LocalLlmChatIntentRouter({
    required LocalLlmService llmService,
    this.fallbackRouter,
    ChatIntentRoutingPromptBuilder promptBuilder =
        const ChatIntentRoutingPromptBuilder(),
    ChatRouteParser parser = const ChatRouteParser(),
  }) : _llmService = llmService,
       _promptBuilder = promptBuilder,
       _parser = parser;

  final LocalLlmService _llmService;
  final ChatIntentRouter? fallbackRouter;
  final ChatIntentRoutingPromptBuilder _promptBuilder;
  final ChatRouteParser _parser;

  @override
  Future<ChatRoute> route(String message) async {
    return routeWithHistory(message);
  }

  @override
  Future<ChatRoute> routeWithHistory(
    String message, {
    List<ConversationMessage> history = const [],
  }) async {
    _log('historyMessageCount=${history.length}');
    try {
      final routerInput = _promptBuilder.build(message, history: history);
      _log('ROUTER INPUT:\n$routerInput');
      final response = StringBuffer();
      await for (final chunk in _llmService.generate(routerInput)) {
        response.write(chunk);
      }
      final rawOutput = response.toString();
      final route = _parser.parse(rawOutput);
      _log('ROUTER RESULT:\n${route.label}');
      return route;
    } catch (_) {
      final fallbackRouter = this.fallbackRouter;
      if (fallbackRouter != null) {
        final route = fallbackRouter is HistoryAwareChatIntentRouter
            ? await fallbackRouter.routeWithHistory(message, history: history)
            : await fallbackRouter.route(message);
        return route;
      }
      return ChatRoute.knowledge;
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[Router] $message');
    }
  }
}
