import 'conversation_message.dart';

class ConversationContextBuilder {
  const ConversationContextBuilder();

  String build(Iterable<ConversationMessage> messages) {
    return messages
        .map(
          (message) => switch (message.author) {
            ConversationAuthor.user => 'User: ${message.text}',
            ConversationAuthor.assistant => 'Assistant: ${message.text}',
          },
        )
        .join('\n');
  }
}
