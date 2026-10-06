import 'package:flutter/material.dart';

import '../ai_chat_configuration.dart';

/// Displays the branded assistant avatar used by the chat welcome state.
class AiAvatar extends StatelessWidget {
  const AiAvatar({
    required this.theme,
    this.assistantName,
    this.assistantAvatar,
    this.radius,
    super.key,
  });

  final AiChatTheme theme;
  final String? assistantName;
  final ImageProvider? assistantAvatar;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: assistantName == null
          ? '${theme.avatarLabel} assistant'
          : '$assistantName avatar',
      image: true,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: theme.primaryColor,
        foregroundImage: assistantAvatar,
        child: Icon(theme.avatarIcon, color: theme.primaryTextColor),
      ),
    );
  }
}
