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
                  cursorColor: theme.buttonColor,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    labelText: 'Ask a question',
                    labelStyle: TextStyle(color: theme.secondaryTextColor),
                    floatingLabelStyle: TextStyle(color: theme.buttonColor),
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
                        color: theme.buttonColor,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SendButton(enabled: enabled, onPressed: onSend, theme: theme),
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
                  color: theme.secondaryTextColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SendButton extends StatelessWidget {
  const SendButton({
    super.key,
    required this.enabled,
    required this.onPressed,
    required this.theme,
  });

  final bool enabled;
  final VoidCallback onPressed;
  final AiChatTheme theme;

  static const double _size = 48;
  static const double _radius = 14;
  static const Duration _duration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final bg = enabled
        ? theme.buttonColor
        : theme.secondaryTextColor.withValues(alpha: .12);
    final fg = enabled
        ? theme.buttonTextColor
        : theme.secondaryTextColor.withValues(alpha: .38);

    return Tooltip(
      message: 'Send message',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: 'Send message',
        child: AnimatedContainer(
          duration: _duration,
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(_radius),
              onTap: enabled ? onPressed : null,
              child: Center(
                child: TweenAnimationBuilder<Color?>(
                  duration: _duration,
                  tween: ColorTween(end: fg),
                  builder: (_, color, __) => Icon(
                    Icons.arrow_upward_rounded,
                    size: 24,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
