import 'package:flutter/material.dart';

/// White-label visual styling for the chat experience.
@immutable
class AiChatTheme {
  const AiChatTheme({
    this.primaryColor = const Color(0xFF3F51B5),
    this.accentColor = const Color(0xFF00A8A8),
    this.backgroundColor = const Color(0xFFF9FAFF),
    this.surfaceColor = Colors.white,
    this.userBubbleColor = const Color(0xFF3F51B5),
    this.assistantBubbleColor = const Color(0xFFF1F3F8),
    this.userTextColor = Colors.white,
    this.assistantTextColor = const Color(0xFF1A1C20),
    this.borderColor = const Color(0xFFD7DBE8),
    this.inputBackgroundColor = Colors.white,
    this.avatarLabel = 'AI',
    this.avatarIcon = Icons.auto_awesome,
    this.bubbleRadius = 18,
    this.spacing = 16,
    this.animationDuration = const Duration(milliseconds: 180),
  });

  final Color primaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color userBubbleColor;
  final Color assistantBubbleColor;
  final Color userTextColor;
  final Color assistantTextColor;
  final Color borderColor;
  final Color inputBackgroundColor;
  final String avatarLabel;
  final IconData avatarIcon;
  final double bubbleRadius;
  final double spacing;
  final Duration animationDuration;
}

/// White-label chat text and UI behavior shared by the app and chat feature.
@immutable
class AiChatConfiguration {
  const AiChatConfiguration({
    this.title = 'Offline Assistant',
    this.welcomeTitle = 'How can I help?',
    this.welcomeMessage = 'Ask a question using your local knowledge base.',
    this.greetingMessage = 'Hi! How can I help you today?',
    this.wellbeingMessage =
        "I'm doing well and ready to help with your technical questions.",
    this.gratitudeMessage = "You're welcome!",
    this.unsupportedQuestionMessage =
        "I'm an AI assistant designed to help with technical information "
        "available in my knowledge base. I can't answer that question.",
    this.suggestions = const [],
    this.showLocalSources = true,
    this.scrollThreshold = 160,
    this.maxHistoryMessages = 6,
  });

  final String title;
  final String welcomeTitle;
  final String welcomeMessage;
  final String greetingMessage;
  final String wellbeingMessage;
  final String gratitudeMessage;
  final String unsupportedQuestionMessage;
  final List<String> suggestions;
  final bool showLocalSources;
  final double scrollThreshold;
  final int maxHistoryMessages;
}
