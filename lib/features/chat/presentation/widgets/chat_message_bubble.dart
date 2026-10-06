import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';

import '../ai_chat_configuration.dart';
import '../assistant_content.dart';
import '../chat_models.dart';

/// Renders one user or assistant message, including its available actions.
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    required this.message,
    required this.theme,
    required this.showSources,
    required this.showGenerationTime,
    required this.showCopyAction,
    required this.showRegenerateAction,
    required this.showRetryAction,
    required this.retryEnabled,
    required this.regenerateEnabled,
    required this.generationTimeLabel,
    required this.assistantName,
    required this.assistantAvatar,
    required this.sourceSectionLabel,
    required this.seenMessages,
    this.onFirstVisibleText,
    required this.onRetry,
    required this.onRegenerate,
    super.key,
  });

  final ChatMessage message;
  final AiChatTheme theme;
  final bool showSources;
  final bool showGenerationTime;
  final bool showCopyAction;
  final bool showRegenerateAction;
  final bool showRetryAction;
  final bool retryEnabled;
  final bool regenerateEnabled;
  final String generationTimeLabel;
  final String assistantName;
  final ImageProvider? assistantAvatar;
  final String sourceSectionLabel;
  final Set<String> seenMessages;
  final void Function(BuildContext)? onFirstVisibleText;
  final VoidCallback onRetry;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final isUser = message.author == ChatAuthor.user;
    final textColor = isUser ? theme.userTextColor : theme.assistantTextColor;
    final showTime =
        !isUser &&
        !message.isStreaming &&
        !message.isError &&
        showGenerationTime &&
        message.generationDuration != null;
    final showCopy =
        showCopyAction &&
        !isUser &&
        !message.isStreaming &&
        !message.isError &&
        message.text.isNotEmpty;
    final showRegenerate =
        showRegenerateAction &&
        !isUser &&
        !message.isStreaming &&
        !message.isError &&
        message.text.isNotEmpty &&
        message.question != null;
    final showRetry =
        showRetryAction &&
        !isUser &&
        !message.isStreaming &&
        message.isError &&
        message.text.isNotEmpty;
    final messageContent = message.isStreaming && message.text.isEmpty
        ? _TypingIndicator(theme: theme)
        : !isUser &&
              !message.isStreaming &&
              !message.isError &&
              message.text.isNotEmpty
        ? AssistantContent(text: message.text, theme: theme)
        : Text(
            message.text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: textColor, height: 1.4),
          );
    final content = Padding(
      padding: EdgeInsets.only(bottom: theme.spacing * .75),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          // if (!isUser) ...[
          //   AiAvatar(
          //     theme: theme,
          //     assistantName: assistantName,
          //     assistantAvatar: assistantAvatar,
          //   ),
          //   const SizedBox(width: 8),
          // ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: isUser ? 'Your message' : 'Assistant message',
                  child: isUser
                      ? Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: theme.spacing,
                            vertical: theme.spacing * .75,
                          ),
                          decoration: BoxDecoration(
                            color: theme.userBubbleColor,
                            borderRadius: BorderRadius.circular(
                              theme.bubbleRadius,
                            ),
                            border: Border.all(
                              color: message.isError
                                  ? theme.primaryColor.withValues(alpha: .65)
                                  : theme.borderColor,
                            ),
                          ),
                          child: messageContent,
                        )
                      : Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: theme.spacing * .75,
                          ),
                          child: onFirstVisibleText == null
                              ? messageContent
                              : Builder(
                                  builder: (contentContext) {
                                    onFirstVisibleText!(contentContext);
                                    return messageContent;
                                  },
                                ),
                        ),
                ),
                if (showTime || showCopy || showRegenerate)
                  Padding(
                    padding: EdgeInsets.only(top: theme.spacing * .01),
                    child: Wrap(
                      spacing: theme.spacing * .5,
                      runSpacing: theme.spacing * .25,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (showTime)
                          Text(
                            '$generationTimeLabel ${(message.generationDuration!.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(2)}s',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: theme.backgroundTextColor.withValues(
                                    alpha: .75,
                                  ),
                                ),
                          ),
                        if (showCopy)
                          CopyTextAction(text: message.text, theme: theme),
                        if (showRegenerate)
                          IconButton(
                            tooltip: 'Regenerate response',
                            onPressed: regenerateEnabled ? onRegenerate : null,
                            icon: const Icon(Icons.refresh),
                            iconSize: 18,
                            style: IconButton.styleFrom(
                              foregroundColor: theme.backgroundTextColor
                                  .withValues(alpha: .75),
                              minimumSize: const Size(36, 36),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    ),
                  ),
                if (!isUser &&
                    !message.isStreaming &&
                    !message.isError &&
                    showSources &&
                    message.sources.isNotEmpty)
                  _MessageSources(
                    sources: message.sources,
                    label: sourceSectionLabel,
                    theme: theme,
                  ),
                if (showRetry)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.primaryColor,
                    ),
                    onPressed:
                        retryEnabled &&
                            message.question?.trim().isNotEmpty == true
                        ? onRetry
                        : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return _MessageEntrance(
      key: ValueKey('entrance-${message.id}'),
      messageId: message.id,
      seenMessages: seenMessages,
      duration: theme.animationDuration,
      child: content,
    );
  }
}

class _MessageSources extends StatelessWidget {
  const _MessageSources({
    required this.sources,
    required this.label,
    required this.theme,
  });

  final List<KnowledgeDocument> sources;
  final String label;
  final AiChatTheme theme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final metadataColor = theme.backgroundTextColor.withValues(alpha: .75);
    return Padding(
      padding: EdgeInsets.only(top: theme.spacing * .5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label · ${sources.length}',
            style: textTheme.bodySmall?.copyWith(color: metadataColor),
          ),
          SizedBox(height: theme.spacing * .25),
          for (final source in sources)
            Padding(
              padding: EdgeInsets.only(bottom: theme.spacing * .25),
              child: Text(switch (source.metadata['code']) {
                final String code when code.trim().isNotEmpty =>
                  '${code.trim()} — ${source.title}',
                _ => source.title,
              }, style: textTheme.bodySmall?.copyWith(color: metadataColor)),
            ),
        ],
      ),
    );
  }
}

class _MessageEntrance extends StatefulWidget {
  const _MessageEntrance({
    required this.messageId,
    required this.seenMessages,
    required this.duration,
    required this.child,
    super.key,
  });

  final String messageId;
  final Set<String> seenMessages;
  final Duration duration;
  final Widget child;

  @override
  State<_MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<_MessageEntrance> {
  late final bool _animate = widget.seenMessages.add(widget.messageId);

  @override
  Widget build(BuildContext context) {
    if (!_animate || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: widget.duration,
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 6),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.theme});

  final AiChatTheme theme;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController = AnimationController(
    vsync: this,
    duration: widget.theme.animationDuration * 4,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animationController.stop();
    } else if (!_animationController.isAnimating &&
        _animationController.duration != Duration.zero) {
      _animationController.repeat();
    }
  }

  @override
  void didUpdateWidget(_TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.theme.animationDuration != oldWidget.theme.animationDuration) {
      _animationController.duration = widget.theme.animationDuration * 4;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _animationController.stop();
        if (_animationController.duration != Duration.zero) {
          _animationController.repeat();
        }
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Thinking…',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Thinking ',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: widget.theme.assistantTextColor,
              ),
            ),
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (index) {
                  final phase = _animationController.value - index / 3;
                  final opacity = MediaQuery.disableAnimationsOf(context)
                      ? 1.0
                      : .4 + .6 * (1 + math.sin(phase * 2 * math.pi)) / 2;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Opacity(
                      opacity: opacity,
                      child: CircleAvatar(
                        radius: 3,
                        backgroundColor: widget.theme.assistantTextColor,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
