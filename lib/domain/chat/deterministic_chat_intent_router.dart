import '../rag/chat_intent_classifier.dart';
import 'chat_intent_router.dart';
import 'chat_route.dart';

class DeterministicChatIntentRouter implements ChatIntentRouter {
  const DeterministicChatIntentRouter({
    ChatIntentClassifier classifier = const ChatIntentClassifier(),
  }) : _classifier = classifier;

  final ChatIntentClassifier _classifier;

  @override
  Future<ChatRoute> route(String message) async {
    final intent = _classifier.classify(message);
    return intent == ChatIntent.knowledge
        ? ChatRoute.knowledge
        : ChatRoute.chat;
  }
}
