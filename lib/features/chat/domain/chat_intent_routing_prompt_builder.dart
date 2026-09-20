import 'conversation_context_builder.dart';
import 'conversation_message.dart';

class ChatIntentRoutingPromptBuilder {
  const ChatIntentRoutingPromptBuilder({
    ConversationContextBuilder contextBuilder =
        const ConversationContextBuilder(),
  }) : _contextBuilder = contextBuilder;

  final ConversationContextBuilder _contextBuilder;

  String build(String message, {List<ConversationMessage> history = const []}) {
    return '''You are a routing classifier.

Classify the user message as one of these two labels:

CHAT
KNOWLEDGE

CHAT means casual conversation, greetings, thanks, or wellbeing.

KNOWLEDGE means the user needs technical information from a local knowledge base.

Choose exactly one label: CHAT or KNOWLEDGE

Do not respond with anything other than the label.

<conversation_history>
${_contextBuilder.build(history)}
</conversation_history>

<current_user_message>
$message
</current_user_message>

Classify the current user message using the conversation history only for context.
Respond with only CHAT or KNOWLEDGE:
''';
  }
}
