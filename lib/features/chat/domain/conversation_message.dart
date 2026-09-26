enum ConversationAuthor { user, assistant }

class ConversationMessage {
  const ConversationMessage({
    required this.author,
    required this.text,
    this.turnId,
  });

  final ConversationAuthor author;
  final String text;
  final String? turnId;
}
