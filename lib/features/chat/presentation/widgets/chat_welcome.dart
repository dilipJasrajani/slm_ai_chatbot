import 'package:flutter/material.dart';

import '../ai_chat_configuration.dart';
import 'ai_avatar.dart';

/// Displays the empty-conversation welcome state and suggested questions.
class ChatWelcome extends StatelessWidget {
  const ChatWelcome({
    required this.configuration,
    required this.theme,
    required this.enabled,
    required this.onSuggestion,
    super.key,
  });

  final AiChatConfiguration configuration;
  final AiChatTheme theme;
  final bool enabled;
  final ValueChanged<String> onSuggestion;

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
              if (configuration.suggestions.isNotEmpty) ...[
                SizedBox(height: theme.spacing),
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: theme.spacing * .5,
                    runSpacing: theme.spacing * .5,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final suggestion in configuration.suggestions)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth,
                          ),
                          child: ActionChip(
                            label: Text(suggestion, softWrap: true),
                            backgroundColor: theme.surfaceColor,
                            side: BorderSide(color: theme.accentColor),
                            labelStyle: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: enabled
                                      ? theme.surfaceTextColor
                                      : theme.surfaceTextColor.withValues(
                                          alpha: .6,
                                        ),
                                ),
                            onPressed: enabled
                                ? () => onSuggestion(suggestion)
                                : null,
                          ),
                        ),
                    ],
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
