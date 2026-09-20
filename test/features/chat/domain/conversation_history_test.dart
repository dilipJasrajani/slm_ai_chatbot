import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_intent_routing_prompt_builder.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_context_builder.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_history.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_message.dart';

void main() {
  test('keeps the newest messages in order and clears them', () {
    final history = InMemoryConversationHistory(maxMessages: 3);

    history.addAll(const [
      ConversationMessage(author: ConversationAuthor.user, text: 'one'),
      ConversationMessage(author: ConversationAuthor.assistant, text: 'two'),
      ConversationMessage(author: ConversationAuthor.user, text: 'three'),
      ConversationMessage(author: ConversationAuthor.assistant, text: 'four'),
    ]);

    expect(history.messages.map((message) => message.text), [
      'two',
      'three',
      'four',
    ]);
    history.clear();
    expect(history.messages, isEmpty);
  });

  test('router prompt includes delimited conversation history', () {
    final prompt = const ChatIntentRoutingPromptBuilder().build(
      'What about that error?',
      history: const [
        ConversationMessage(author: ConversationAuthor.user, text: 'E123'),
        ConversationMessage(
          author: ConversationAuthor.assistant,
          text: 'Check the network.',
        ),
      ],
    );

    expect(prompt, contains('<conversation_history>'));
    expect(prompt, contains('User: E123'));
    expect(prompt, contains('Assistant: Check the network.'));
    expect(prompt, contains('<current_user_message>'));
    expect(prompt, contains('What about that error?'));
  });

  test('context builder produces an empty context for empty history', () {
    expect(const ConversationContextBuilder().build(const []), isEmpty);
  });
}
