import 'chat_route.dart';
import 'conversation_message.dart';

abstract interface class ChatIntentRouter {
  Future<ChatRoute> route(String message);
}

abstract interface class HistoryAwareChatIntentRouter
    implements ChatIntentRouter {
  Future<ChatRoute> routeWithHistory(
    String message, {
    List<ConversationMessage> history = const [],
  });
}
