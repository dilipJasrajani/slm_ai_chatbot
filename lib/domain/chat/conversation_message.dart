enum ConversationAuthor { user, assistant }

class ConversationMessage {
  const ConversationMessage({required this.author, required this.text});

  final ConversationAuthor author;
  final String text;
}
