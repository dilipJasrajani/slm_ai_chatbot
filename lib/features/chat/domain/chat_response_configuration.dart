class ChatResponseConfiguration {
  const ChatResponseConfiguration({
    this.greetingMessage = 'Hi! How can I help you today?',
    this.wellbeingMessage =
        "I'm doing well and ready to help with your technical questions.",
    this.gratitudeMessage = "You're welcome!",
    this.unsupportedQuestionMessage =
        "I'm an AI assistant designed to help with technical information "
        "available in my knowledge base. I can't answer that question.",
  });

  final String greetingMessage;
  final String wellbeingMessage;
  final String gratitudeMessage;
  final String unsupportedQuestionMessage;
}
