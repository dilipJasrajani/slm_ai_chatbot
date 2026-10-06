import 'package:flutter/foundation.dart';

import 'package:slm_ai_chatbot/features/model/domain/model_status.dart';

import '../models/chat_message.dart';

@immutable
/// Immutable presentation state emitted by ChatCubit and rendered by AiChatPage.
/// Identity equality preserves every update, including identical text chunks.
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
