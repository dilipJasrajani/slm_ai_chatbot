import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_message.dart';
import 'package:slm_ai_chatbot/features/rag/domain/retrieval_query_builder.dart';

void main() {
  const builder = RetrievalQueryBuilder();
  const history = [
    ConversationMessage(
      author: ConversationAuthor.user,
      text: 'What does error F.867 mean?',
    ),
    ConversationMessage(
      author: ConversationAuthor.assistant,
      text: 'Potentially incorrect generated text about F.425.',
    ),
  ];

  test('self-contained questions ignore previous user and assistant text', () {
    for (final question in [
      'What does error F.425 mean?',
      'What should I check if the heat pump switches off during venting?',
      'Why is this heat pump switching off during venting?',
      'How can I fix low water pressure?',
      'Tell me more about hydraulic pressure.',
      'Compare F.425 and F.867.',
    ]) {
      expect(builder.build(question: question, history: history), question);
    }
  });

  test('explicit new code takes precedence over previous subject', () {
    final resolved = builder.resolve(
      question: 'What about F.425?',
      history: history,
    );
    expect(resolved.question, 'What does error F.425 mean?');
    expect(resolved.identifiers, {'F425'});
  });

  test('product names, quantities and part numbers are not fault targets', () {
    final semantic = builder.resolve(
      question: 'Check CR2032 battery on Vitocal 252-A with pressure 2 bar',
      history: history,
    );
    expect(semantic.identifiers, isEmpty);
    final fault = builder.resolve(
      question: 'What does F.867 mean on Vitocal 252-A?',
      history: history,
    );
    expect(fault.identifiers, {'F867'});
    expect(
      builder.resolve(question: 'What does error ABC123 mean?').identifiers,
      {'ABC123'},
    );
  });

  test('resolves a follow-up using the user subject, not generated codes', () {
    final query = builder.build(question: 'How do I fix it?', history: history);
    expect(query, 'How do I fix fault F867?');
    expect(
      builder.build(question: 'How do I fix it?', history: history),
      query,
    );
  });

  test('most recent single-code subject wins over an older issue', () {
    expect(
      builder.build(
        question: 'How do I fix it?',
        history: [
          ...history,
          const ConversationMessage(
            author: ConversationAuthor.user,
            text: 'What about F.425?',
          ),
        ],
      ),
      'How do I fix fault F425?',
    );
  });

  test(
    'multiple plausible subjects require clarification without searching',
    () {
      final messages = [
        const ConversationMessage(
          author: ConversationAuthor.user,
          text: 'Compare F.425 and F.867.',
        ),
      ];
      final result = builder.resolve(
        question: 'How do I fix it?',
        history: messages,
      );
      expect(result.clarification, contains('Which fault code'));
      expect(
        () => builder.build(question: 'How do I fix it?', history: messages),
        throwsStateError,
      );
    },
  );

  test('missing subject is not guessed from an assistant answer', () {
    expect(
      builder
          .resolve(question: 'How do I fix it?', history: [history.last])
          .clarification,
      isNotNull,
    );
  });

  test('ordinary semantic follow-ups keep only the recent user subject', () {
    final query = builder.build(
      question: 'Tell me more.',
      history: const [
        ConversationMessage(
          author: ConversationAuthor.user,
          text: 'Why is hydraulic pressure low?',
        ),
        ConversationMessage(
          author: ConversationAuthor.assistant,
          text: 'An unsupported cause.',
        ),
      ],
    );
    expect(query, 'Tell me more.\nSubject: Why is hydraulic pressure low?');
    expect(query, isNot(contains('unsupported')));
  });
}
