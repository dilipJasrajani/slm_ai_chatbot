class ChatIntentRoutingPromptBuilder {
  const ChatIntentRoutingPromptBuilder();

  String build(String message) {
    print(''' this is message ================= $message ''');
    return '''You are a routing classifier.

Classify the user message as one of these two labels:

CHAT
KNOWLEDGE

CHAT means casual conversation, greetings, thanks, or wellbeing.

KNOWLEDGE means the user needs technical information from a local knowledge base.

Choose exactly one label: CHAT or KNOWLEDGE

Do not respond with anything else then above label

Classify the following user message and respond with only the above label for message: $message
''';
  }
}
