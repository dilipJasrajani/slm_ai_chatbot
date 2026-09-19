import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/domain/rag/rag_prompt_builder.dart';

void main() {
  test('builds a deterministic prompt with rules context and question', () {
    final prompt = const RagPromptBuilder().build(
      question: 'What does E123 mean?',
      context: 'Knowledge Document 1\n\nTitle:\nNetwork guide',
    );

    expect(prompt, contains('Do not invent facts'));
    expect(prompt, contains('Knowledge Document 1'));
    expect(prompt, contains('What does E123 mean?'));
    expect(
      const RagPromptBuilder().build(
        question: 'What does E123 mean?',
        context: 'Knowledge Document 1\n\nTitle:\nNetwork guide',
      ),
      prompt,
    );
  });
}
