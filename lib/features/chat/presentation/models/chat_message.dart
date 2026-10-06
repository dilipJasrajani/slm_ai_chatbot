import 'package:flutter/foundation.dart';

import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';

enum ChatAuthor { user, assistant }

@immutable
/// A rendered chat message and its streaming, timing, error, and source metadata.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.author,
    required this.text,
    this.isStreaming = false,
    this.isError = false,
    this.sources = const [],
    this.generationDuration,
    this.question,
  });

  final String id;
  final ChatAuthor author;
  final String text;
  final bool isStreaming;
  final bool isError;
  final List<KnowledgeDocument> sources;
  final Duration? generationDuration;
  final String? question;

  ChatMessage copyWith({
    String? text,
    bool? isStreaming,
    bool? isError,
    List<KnowledgeDocument>? sources,
    Duration? generationDuration,
  }) {
    return ChatMessage(
      id: id,
      author: author,
      text: text ?? this.text,
      isStreaming: isStreaming ?? this.isStreaming,
      isError: isError ?? this.isError,
      sources: sources ?? this.sources,
      generationDuration: generationDuration ?? this.generationDuration,
      question: question,
    );
  }
}
