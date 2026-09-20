import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../../domain/chat/chat_intent_router.dart';
import '../../domain/chat/chat_intent_routing_prompt_builder.dart';
import '../../domain/chat/chat_route.dart';
import '../../domain/chat/chat_route_parser.dart';
import '../../domain/llm/local_llm_service.dart';

class LocalLlmChatIntentRouter implements ChatIntentRouter {
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
    _log('Input: $message');
    try {
      final response = StringBuffer();
      await for (final chunk in _llmService.generate(
        _promptBuilder.build(message),
      )) {
        response.write(chunk);
      }
      final rawOutput = response.toString();
      _log('Raw model output: $rawOutput');
      _log(
        'Raw model output (escaped): '
        '${rawOutput.replaceAll('\\', r'\\').replaceAll('\n', r'\n')}',
      );
      if (tryParseChatRouteLabel(rawOutput) == null) {
        _log('Invalid router output. Defaulting to KNOWLEDGE.');
      }
      final route = _parser.parse(rawOutput);
      _log('Parsed route: ${route.label}');
      return route;
    } catch (_) {
      final fallbackRouter = this.fallbackRouter;
      if (fallbackRouter != null) {
        final route = await fallbackRouter.route(message);
        _log('Parsed route: ${route.label}');
        return route;
      }
      _log('Parsed route: ${ChatRoute.knowledge.label}');
      return ChatRoute.knowledge;
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[Router] $message');
    }
  }
}
