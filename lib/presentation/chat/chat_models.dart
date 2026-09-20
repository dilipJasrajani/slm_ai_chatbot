import 'package:flutter/material.dart';

import '../../domain/model/model_status.dart';

enum ChatAuthor { user, assistant }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.author,
    required this.text,
    this.isStreaming = false,
    this.isError = false,
    this.sourceTitles = const [],
    this.question,
  });

  final String id;
  final ChatAuthor author;
  final String text;
  final bool isStreaming;
  final bool isError;
  final List<String> sourceTitles;
  final String? question;

  ChatMessage copyWith({
    String? text,
    bool? isStreaming,
    bool? isError,
    List<String>? sourceTitles,
  }) {
    return ChatMessage(
      id: id,
      author: author,
      text: text ?? this.text,
      isStreaming: isStreaming ?? this.isStreaming,
      isError: isError ?? this.isError,
      sourceTitles: sourceTitles ?? this.sourceTitles,
      question: question,
    );
  }
}

@immutable
class ChatState {
  const ChatState({
    required this.modelState,
    this.messages = const [],
    this.isTyping = false,
    this.isPreparingKnowledge = false,
    this.knowledgeReady = true,
    this.knowledgeError,
  });

  final ModelState modelState;
  final List<ChatMessage> messages;
  final bool isTyping;
  final bool isPreparingKnowledge;
  final bool knowledgeReady;
  final String? knowledgeError;

  bool get canSend =>
      modelState.status == ModelStatus.ready && knowledgeReady && !isTyping;

  ChatState copyWith({
    ModelState? modelState,
    List<ChatMessage>? messages,
    bool? isTyping,
    bool? isPreparingKnowledge,
    bool? knowledgeReady,
    String? knowledgeError,
    bool clearKnowledgeError = false,
  }) {
    return ChatState(
      modelState: modelState ?? this.modelState,
      messages: messages ?? this.messages,
      isTyping: isTyping ?? this.isTyping,
      isPreparingKnowledge: isPreparingKnowledge ?? this.isPreparingKnowledge,
      knowledgeReady: knowledgeReady ?? this.knowledgeReady,
      knowledgeError: clearKnowledgeError
          ? null
          : knowledgeError ?? this.knowledgeError,
    );
  }
}

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
}
