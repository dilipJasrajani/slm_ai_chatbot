import 'package:flutter/foundation.dart';

import 'package:slm_ai_chatbot/features/model/domain/model_status.dart';

enum ChatAuthor { user, assistant }

@immutable
/// A rendered chat message and its streaming, error, and source metadata.
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
/// Immutable presentation state observed by [ChatController] and [AiChatPage].
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
