import 'package:flutter/material.dart';

import '../ai_chat_configuration.dart';
import 'ai_avatar.dart';

/// Displays the empty-conversation welcome state.
class ChatWelcome extends StatelessWidget {
  const ChatWelcome({
    required this.configuration,
    required this.theme,
    super.key,
  });

  final AiChatConfiguration configuration;
  final AiChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(theme.spacing * 1.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AiAvatar(
                theme: theme,
                assistantName: configuration.assistantName,
                assistantAvatar: configuration.assistantAvatar,
                radius: theme.spacing * 2,
              ),
              if (configuration.assistantName.isNotEmpty) ...[
                SizedBox(height: theme.spacing * .75),
                Text(
                  configuration.assistantName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: theme.backgroundTextColor,
                  ),
                ),
              ],
              if (configuration.welcomeTitle.isNotEmpty) ...[
                SizedBox(height: theme.spacing * .5),
                Text(
                  configuration.welcomeTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: theme.backgroundTextColor,
                  ),
                ),
              ],
              if (configuration.welcomeMessage.isNotEmpty) ...[
                SizedBox(height: theme.spacing * .5),
                Text(
                  configuration.welcomeMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: theme.backgroundTextColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
