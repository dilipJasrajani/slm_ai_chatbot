import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_message.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_prompt_builder.dart';

void main() {
  test('instructs the model not to echo input delimiters', () {
    final prompt = const RagPromptBuilder().build(
      question: 'What does F.867 mean?',
      context: 'Documented fault details.',
    );

    expect(prompt, contains('Output only the user-facing answer'));
    expect(
      prompt,
      contains(
        'target_fault_codes, knowledge, and current_user_question tags '
        'are input delimiters only',
      ),
    );
    expect(prompt, contains('Never include their opening or closing tags'));
    expect(prompt, contains('or wrap your answer in XML/HTML tags'));
    expect(
      prompt.lastIndexOf('Do not output any input delimiter tags'),
      greaterThan(prompt.lastIndexOf('</current_user_question>')),
    );
  });

  test('prioritizes the current question and keeps cases distinct', () {
    final prompt = const RagPromptBuilder().build(
      question: 'What does E123 mean on this model?',
      context: 'Knowledge Document 1\n\nTitle:\nNetwork guide',
      history: const [
        ConversationMessage(
          author: ConversationAuthor.user,
          text: 'How do I fix E456?',
        ),
      ],
    );

    expect(prompt, contains('Prioritize the current question'));
    expect(prompt, contains('treat it as a new case'));
    expect(prompt, contains('Do not carry over a previous diagnosis'));
    expect(prompt, contains('Never combine causes, symptoms, or repair steps'));
    expect(prompt, contains('Recommend a repair or replacement only when'));
    expect(prompt, contains('ask for the exact product/model and error code'));
    expect(prompt, contains('What does E123 mean on this model?'));
    expect(prompt, isNot(contains('How do I fix E456?')));
    expect(prompt, isNot(contains('<conversation_history>')));
    expect(prompt, contains('Knowledge Document 1'));
  });

  test('limits bold formatting in recommended steps', () {
    final prompt = const RagPromptBuilder().build(
      question: 'How do I resolve this?',
      context: 'Documented repair steps',
    );

    expect(
      prompt,
      contains('bold at most one item, once: the action verb or key part name'),
    );
    expect(prompt, contains('Do not bold the whole bullet'));
  });

  test('preserves grounding and safety independent of answer formatting', () {
    final prompt = const RagPromptBuilder().build(
      question: 'How should I explain the fault and its repair?',
      context: 'Documented cause and repair procedure',
    );

    expect(prompt, contains('qualification requirements'));
    expect(prompt, contains('without weakening or omitting'));
    expect(prompt, contains('separate labelled section'));
    expect(prompt, contains('original source instructions'));
  });

  test('instructs concise follow-up answers and grounded uncertainty', () {
    final prompt = const RagPromptBuilder().build(
      question: 'What is the resolution for E123?',
      context: 'Documented resolution only',
      history: const [
        ConversationMessage(
          author: ConversationAuthor.assistant,
          text: 'Previously explained cause and behavior.',
        ),
      ],
    );

    expect(prompt, contains('answer only what is asked'));
    expect(
      prompt,
      contains('do not repeat the earlier answer unless requested'),
    );
    expect(prompt, contains('say it is unavailable'));
    expect(prompt, contains('provide supported parts'));
    expect(prompt, contains('Documented resolution only'));
    expect(prompt, contains('What is the resolution for E123?'));
    expect(prompt, isNot(contains('Previously explained cause and behavior.')));
  });

  test('builds the same prompt for the same inputs', () {
    const builder = RagPromptBuilder();
    const question = 'What does E123 mean?';
    const context = 'Knowledge Document 1\n\nTitle:\nNetwork guide';

    expect(
      builder.build(question: question, context: context),
      builder.build(question: question, context: context),
    );
  });
}
