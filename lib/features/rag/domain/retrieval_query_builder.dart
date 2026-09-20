import 'package:slm_ai_chatbot/features/chat/domain/conversation_context_builder.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_message.dart';

/// Builds the vector-search query from the current question and prior context.
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
