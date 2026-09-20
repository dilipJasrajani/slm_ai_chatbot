class ConversationalPromptBuilder {
  const ConversationalPromptBuilder();

  String build(String message) {
    return '''You are a friendly offline assistant.

Reply naturally to the user's message.
Keep the answer concise and helpful.

User message:
$message

Answer:''';
  }
}
