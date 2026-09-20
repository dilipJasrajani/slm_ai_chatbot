import 'package:slm_ai_chatbot/features/chat/domain/conversation_context_builder.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_message.dart';

class RagPromptBuilder {
  const RagPromptBuilder({
    ConversationContextBuilder contextBuilder =
        const ConversationContextBuilder(),
  }) : _contextBuilder = contextBuilder;

  final ConversationContextBuilder _contextBuilder;

  String build({
    required String question,
    required String context,
    List<ConversationMessage> history = const [],
  }) {
    return '''You are a technical knowledge assistant.

Answer the user's question using the provided knowledge.

Rules:
- Use the provided knowledge as the primary source.
- Do not invent facts that are not supported by the provided knowledge.
- If the knowledge does not contain enough information to answer, say that the information is not available in the knowledge base.
- Keep the answer concise and useful.

<conversation_history>
${_contextBuilder.build(history)}
</conversation_history>

<knowledge>
$context
</knowledge>

<current_user_question>
$question
</current_user_question>

Answer:''';
  }
}
