import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'package:slm_ai_chatbot/core/profiling/ai_latency_profile.dart';
import '../domain/chat_intent_router.dart';
import '../domain/chat_intent_routing_prompt_builder.dart';
import '../domain/chat_route.dart';
import '../domain/chat_route_parser.dart';
import '../domain/conversation_message.dart';
import 'package:slm_ai_chatbot/features/llm/domain/local_llm_service.dart';

/// Uses the local LLM and existing routing prompt to classify a user request.
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
    final profile = AiLatencyProfile.current;
    _log('historyMessageCount=${history.length}');
    try {
      final routerInput = _promptBuilder.build(message, history: history);
      profile?.routerPromptCharacters = routerInput.length;
      _log('routerPromptCharacters=${routerInput.length}');
      final response = StringBuffer();
      profile?.generationPhase = AiGenerationPhase.router;
      await for (final chunk in _llmService.generate(routerInput)) {
        response.write(chunk);
      }
      final rawOutput = response.toString();
      profile?.routerOutputCharacters = rawOutput.length;
      final route = _parser.parse(rawOutput);
      _log('routerOutputCharacters=${rawOutput.length} route=${route.label}');
      return route;
    } catch (_) {
      if (profile != null) profile.routerFallback = true;
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
