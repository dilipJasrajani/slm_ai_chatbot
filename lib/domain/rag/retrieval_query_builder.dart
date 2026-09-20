import '../chat/conversation_context_builder.dart';
import '../chat/conversation_message.dart';

class RetrievalQueryBuilder {
  const RetrievalQueryBuilder({
    ConversationContextBuilder conversationContextBuilder =
        const ConversationContextBuilder(),
  }) : _conversationContextBuilder = conversationContextBuilder;

  final ConversationContextBuilder _conversationContextBuilder;

  String build({
    required String question,
    Iterable<ConversationMessage> history = const [],
  }) {
    final context = _conversationContextBuilder.build(history);
    return context.isEmpty ? question : '$context\nUser: $question';
  }
}
