import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'conversation_message.dart';

abstract interface class ConversationHistory {
  List<ConversationMessage> get messages;

  void addAll(Iterable<ConversationMessage> messages);

  void replaceTurn(String turnId, String? answer);

  void clear();
}

class InMemoryConversationHistory implements ConversationHistory {
  InMemoryConversationHistory({this.maxMessages = 6})
    : assert(maxMessages > 0, 'maxMessages must be greater than zero');

  final int maxMessages;
  final List<ConversationMessage> _messages = [];

  @override
  List<ConversationMessage> get messages => List.unmodifiable(_messages);

  @override
  void addAll(Iterable<ConversationMessage> messages) {
    _messages.addAll(messages);
    final overflow = _messages.length - maxMessages;
    if (overflow > 0) {
      _messages.removeRange(0, overflow);
    }
    _logCount();
  }

  @override
  void replaceTurn(String turnId, String? answer) {
    final assistantIndex = _messages.indexWhere(
      (message) =>
          message.turnId == turnId &&
          message.author == ConversationAuthor.assistant,
    );
    if (assistantIndex < 0) {
      throw StateError('Turn $turnId is not in conversation history.');
    }
    if (answer == null) {
      _messages.removeWhere((message) => message.turnId == turnId);
    } else {
      _messages[assistantIndex] = ConversationMessage(
        author: ConversationAuthor.assistant,
        text: answer,
        turnId: turnId,
      );
    }
    _logCount();
  }

  @override
  void clear() {
    _messages.clear();
    _logCount();
  }

  void _logCount() {
    if (kDebugMode) {
      debugPrint('[ConversationHistory] messageCount=${_messages.length}');
    }
  }
}
