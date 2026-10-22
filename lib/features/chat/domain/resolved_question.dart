import 'package:slm_ai_chatbot/features/rag/domain/knowledge_identifier_normalizer.dart';

import 'conversation_message.dart';

/// The same self-contained intent is used for search, grounding and generation.
class ResolvedQuestion {
  const ResolvedQuestion({
    required this.question,
    required this.identifiers,
    this.clarification,
  });

  final String question;
  final Set<String> identifiers;
  final String? clarification;
}

class QuestionResolver {
  const QuestionResolver();

  static const _normalizer = KnowledgeIdentifierNormalizer();
  static final _whatAbout = RegExp(r'^what about\s+', caseSensitive: false);
  static final _reference = RegExp(
    r'\b(it|they|them)\b|'
    r'\b(this|that|these|those)(\s+(fault|error|issue|problem|code)s?)?[?!.]*$|'
    r'^(what|explain|describe)\b.*\b(its|their)\b|'
    r'^(why|tell me more|more details|(can you )?elaborate|'
    r'what (is|are) the (resolution|cause|solution|steps)|'
    r'how (do|can|should) i (fix|resolve|repair)'
    r'(\s+(the )?(fault|error|issue|problem))?)[?!.]*$',
    caseSensitive: false,
  );
  static final _pleasantry = RegExp(
    r'^(hi|hello|hey|thanks|thank you|okay|ok|great|bye)[.! ]*$',
    caseSensitive: false,
  );

  ResolvedQuestion resolve(
    String question, {
    Iterable<ConversationMessage> history = const [],
  }) {
    final identifiers = _normalizer.extractFaultCodes(question);
    if (identifiers.isNotEmpty) {
      final subject = question
          .trim()
          .replaceFirst(_whatAbout, '')
          .replaceAll(RegExp(r'[?]+$'), '');
      final resolved = _whatAbout.hasMatch(question.trim())
          ? 'What does error $subject mean?'
          : question;
      return ResolvedQuestion(question: resolved, identifiers: identifiers);
    }
    if (!_reference.hasMatch(question.trim())) {
      return ResolvedQuestion(question: question, identifiers: const {});
    }

    // Generated answers may contain mistakes or mention unrelated codes.
    for (final message in history.toList().reversed) {
      if (message.author != ConversationAuthor.user ||
          _pleasantry.hasMatch(message.text.trim())) {
        continue;
      }
      final subjects = _normalizer.extractFaultCodes(message.text);
      if (subjects.length > 1) {
        return ResolvedQuestion(
          question: question,
          identifiers: const {},
          clarification:
              'Which fault code do you mean: ${subjects.join(', ')}?',
        );
      }
      if (subjects.isNotEmpty) {
        final subject = 'fault ${subjects.single}';
        final resolved = question.replaceAll(
          RegExp(r'\b(it|this|that)\b', caseSensitive: false),
          subject,
        );
        return ResolvedQuestion(
          question: resolved == question
              ? '$question\nSubject: $subject'
              : resolved,
          identifiers: subjects,
        );
      }
      if (!_reference.hasMatch(message.text.trim())) {
        return ResolvedQuestion(
          question: '$question\nSubject: ${message.text}',
          identifiers: const {},
        );
      }
    }
    return ResolvedQuestion(
      question: question,
      identifiers: const {},
      clarification: 'Which fault or topic are you referring to?',
    );
  }
}
