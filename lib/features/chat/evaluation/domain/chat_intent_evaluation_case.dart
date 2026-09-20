import '../../domain/chat_route.dart';

class ChatIntentEvaluationCase {
  const ChatIntentEvaluationCase({
    required this.id,
    required this.message,
    required this.expectedRoute,
  });

  final String id;
  final String message;
  final ChatRoute expectedRoute;
}
