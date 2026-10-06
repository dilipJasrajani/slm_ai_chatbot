import 'package:flutter/material.dart';

import '../ai_chat_configuration.dart';

/// Collects and submits the next user message.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.theme,
    required this.modelLabel,
    required this.runtimeBackend,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  final AiChatTheme theme;
  final String? modelLabel;
  final String? runtimeBackend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(theme.spacing * .75),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: theme.inputTextColor),
                  cursorColor: theme.primaryColor,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    labelText: 'Ask a question',
                    labelStyle: TextStyle(
                      color: theme.inputTextColor.withValues(alpha: .75),
                    ),
                    floatingLabelStyle: TextStyle(color: theme.primaryColor),
                    filled: true,
                    fillColor: theme.inputBackgroundColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(theme.bubbleRadius),
                      borderSide: BorderSide(color: theme.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(theme.bubbleRadius),
                      borderSide: BorderSide(color: theme.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(theme.bubbleRadius),
                      borderSide: BorderSide(
                        color: theme.primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send message',
                onPressed: enabled ? onSend : null,
                style: IconButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: theme.primaryTextColor,
                ),
                icon: const Icon(Icons.send),
              ),
            ],
          ),
          if (modelLabel != null)
            Padding(
              padding: EdgeInsets.only(top: theme.spacing * .4),
              child: Text(
                runtimeBackend == null
                    ? modelLabel!
                    : '$modelLabel · $runtimeBackend',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: theme.backgroundTextColor.withValues(alpha: .75),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
