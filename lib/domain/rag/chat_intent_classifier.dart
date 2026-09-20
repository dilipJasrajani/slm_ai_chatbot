enum ChatIntent { greeting, wellbeing, gratitude, knowledge }

class ChatIntentClassifier {
  const ChatIntentClassifier();

  static final _greetingPattern = RegExp(
    r'^(?:hi|hello|hey)(?:\s+there)?[!,.?\s]*$|^good\s+(?:morning|afternoon|evening)[!,.?\s]*$',
    caseSensitive: false,
  );
  static final _wellbeingPattern = RegExp(
    r"^(?:how are you|how are you doing|what's up)[!,.?\s]*$",
    caseSensitive: false,
  );
  static final _gratitudePattern = RegExp(
    r"^(?:thanks|thank you|you're helpful)[!,.?\s]*$",
    caseSensitive: false,
  );

  ChatIntent classify(String message) {
    final normalizedMessage = message.trim().replaceAll('\u2019', "'");
    if (_greetingPattern.hasMatch(normalizedMessage)) {
      return ChatIntent.greeting;
    }
    if (_wellbeingPattern.hasMatch(normalizedMessage)) {
      return ChatIntent.wellbeing;
    }
    if (_gratitudePattern.hasMatch(normalizedMessage)) {
      return ChatIntent.gratitude;
    }
    return ChatIntent.knowledge;
  }
}
