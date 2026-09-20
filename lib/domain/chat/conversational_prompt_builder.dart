import 'conversation_context_builder.dart';
import 'conversation_message.dart';

class ConversationalPromptBuilder {
  const ConversationalPromptBuilder({
    ConversationContextBuilder contextBuilder =
        const ConversationContextBuilder(),
  }) : _contextBuilder = contextBuilder;

  final ConversationContextBuilder _contextBuilder;

  String build(String message, {List<ConversationMessage> history = const []}) {
    return '''You are a friendly offline assistant.

Reply naturally to the current user's message.
Keep the answer concise and helpful.

<conversation_history>
${_contextBuilder.build(history)}
</conversation_history>

<current_user_message>
$message
</current_user_message>

Answer:''';
  }
}
