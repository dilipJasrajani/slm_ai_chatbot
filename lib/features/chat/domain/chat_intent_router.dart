import 'chat_route.dart';
import 'conversation_message.dart';

/// Classifies a user request as conversational chat or knowledge seeking.
abstract interface class ChatIntentRouter {
  Future<ChatRoute> route(String message);
}

/// Lets routing use prior conversation as context when the implementation supports it.
abstract interface class HistoryAwareChatIntentRouter
    implements ChatIntentRouter {
  Future<ChatRoute> routeWithHistory(
    String message, {
    List<ConversationMessage> history = const [],
  });
}
