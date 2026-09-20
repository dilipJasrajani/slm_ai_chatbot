import 'chat_route.dart';

class ChatRouteParser {
  const ChatRouteParser();

  ChatRoute parse(String response) {
    return tryParseChatRouteLabel(response) ?? ChatRoute.knowledge;
  }
}
