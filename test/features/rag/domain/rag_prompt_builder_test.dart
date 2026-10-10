import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_prompt_builder.dart';

void main() {
  test('builds a deterministic prompt with rules context and question', () {
    final prompt = const RagPromptBuilder().build(
      question: 'What does E123 mean?',
      context: 'Knowledge Document 1\n\nTitle:\nNetwork guide',
    );

    expect(
      prompt,
      contains(
        'Do not invent, assume, or add facts that are not supported by the provided knowledge.',
      ),
    );
    expect(prompt, contains('Answer from the supported facts first'));
    expect(prompt, contains('briefly identify that missing detail'));
    expect(
      prompt,
      isNot(contains('The information is not available in the knowledge base.')),
    );
    expect(prompt, contains('Knowledge Document 1'));
    expect(prompt, contains('What does E123 mean?'));
    final headings = [
      '  ## Cause',
      '  ## System behavior',
      '  ## Recommended steps',
      '  ## Additional details',
    ];
    for (var index = 1; index < headings.length; index++) {
      expect(
        prompt.indexOf(headings[index]),
        greaterThan(prompt.indexOf(headings[index - 1])),
      );
    }
    expect(
      prompt,
      contains('Omit unsupported or irrelevant sections entirely'),
    );
    expect(
      prompt,
      contains('Start directly with the first applicable heading'),
    );
    expect(prompt, contains('numbered list only when order matters'));
    expect(
      const RagPromptBuilder().build(
        question: 'What does E123 mean?',
        context: 'Knowledge Document 1\n\nTitle:\nNetwork guide',
      ),
      prompt,
    );
  });
}
