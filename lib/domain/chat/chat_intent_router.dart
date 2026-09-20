import 'chat_route.dart';

abstract interface class ChatIntentRouter {
  Future<ChatRoute> route(String message);
}
