import 'package:slm_ai_chatbot/features/chat/domain/conversation_context_builder.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_message.dart';
import 'package:slm_ai_chatbot/features/chat/domain/resolved_question.dart';

/// Builds the vector-search query from the current question and prior context.
class RetrievalQueryBuilder {
  const RetrievalQueryBuilder({
    ConversationContextBuilder conversationContextBuilder =
        const ConversationContextBuilder(),
  });

  ResolvedQuestion resolve({
    required String question,
    Iterable<ConversationMessage> history = const [],
  }) => const QuestionResolver().resolve(question, history: history);

  String build({
    required String question,
    Iterable<ConversationMessage> history = const [],
  }) {
    final resolved = resolve(question: question, history: history);
    if (resolved.clarification != null) {
      throw StateError(resolved.clarification!);
    }
    return resolved.question;
  }
}
