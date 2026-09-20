enum ChatRoute { chat, knowledge }

extension ChatRouteLabel on ChatRoute {
  String get label => switch (this) {
    ChatRoute.chat => 'CHAT',
    ChatRoute.knowledge => 'KNOWLEDGE',
  };
}

ChatRoute? tryParseChatRouteLabel(String value) {
  final normalized = value
      .replaceAll(r'\r', ' ')
      .replaceAll(r'\n', ' ')
      .replaceAll(r'\t', ' ')
      .trim()
      .replaceFirst(RegExp(r'^(?:[-*•]\s*|`+\s*)+'), '')
      .trim()
      .toUpperCase();
  final match = RegExp(
    r'^(CHAT|KNOWLEDGE)(?=$|[\s.!?])',
  ).firstMatch(normalized);
  if (match == null) {
    return null;
  }

  final label = match.group(1)!;
  final oppositeLabel = label == 'CHAT' ? 'KNOWLEDGE' : 'CHAT';
  final remainder = normalized.substring(match.end);
  if (RegExp('\\b$oppositeLabel\\b').hasMatch(remainder)) {
    return null;
  }
  return label == 'CHAT' ? ChatRoute.chat : ChatRoute.knowledge;
}
