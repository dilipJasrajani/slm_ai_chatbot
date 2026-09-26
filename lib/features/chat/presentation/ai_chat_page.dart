import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/rendering.dart'
    show MatrixUtils, RenderAbstractViewport;

import 'package:slm_ai_chatbot/features/chat/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/chat/evaluation/domain/chat_intent_evaluation_runner.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_manager.dart';
import 'package:slm_ai_chatbot/features/model/domain/model_status.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';
import 'package:slm_ai_chatbot/features/rag/evaluation/domain/retrieval_evaluation_runner.dart';
import 'ai_chat_configuration.dart';
import 'assistant_content.dart';
import 'chat_controller.dart';
import 'chat_models.dart';

/// Renders the chat experience and forwards user actions to [ChatController].
class AiChatPage extends StatefulWidget {
  const AiChatPage({
    required this.modelManager,
    required this.askQuestion,
    this.configuration = const AiChatConfiguration(),
    this.chatTheme = const AiChatTheme(),
    this.controller,
    this.chatIntentEvaluationRunner,
    this.prepareKnowledgeBase,
    this.retrievalEvaluationRunner,
    this.runtimeBackendLabel,
    super.key,
  });

  final LocalModelManager modelManager;
  final AskQuestionUseCase askQuestion;
  final AiChatConfiguration configuration;
  final AiChatTheme chatTheme;
  final ChatController? controller;
  final ChatIntentEvaluationRunner? chatIntentEvaluationRunner;
  final Future<void> Function()? prepareKnowledgeBase;
  final RetrievalEvaluationRunner? retrievalEvaluationRunner;
  final String? Function()? runtimeBackendLabel;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  late final ChatController _controller;
  late final bool _ownsController;
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
  final _messageWidgets = <String, _ChatBubble>{};
  final _seenMessages = <String>{};
  final _pendingVisibleItems =
      <String, ({int request, BuildContext context})>{};
  AiChatTheme? _resolvedTheme;
  AiChatTheme? _themeSource;
  ColorScheme? _themeColorScheme;
  var _shouldAutoScroll = true;
  var _scrollScheduled = false;
  var _isRunningEvaluation = false;
  double? _bottomInset;

  AiChatTheme get _theme {
    final colorScheme = Theme.of(context).colorScheme;
    if (!identical(_themeSource, widget.chatTheme) ||
        _themeColorScheme != colorScheme) {
      _themeSource = widget.chatTheme;
      _themeColorScheme = colorScheme;
      _resolvedTheme = widget.chatTheme.resolve(colorScheme);
    }
    return _resolvedTheme!;
  }

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        ChatController(
          modelManager: widget.modelManager,
          askQuestion: widget.askQuestion,
          prepareKnowledgeBase: widget.prepareKnowledgeBase,
        );
    _controller.addListener(_onStateChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _pendingVisibleItems.clear();
    _controller.removeListener(_onStateChanged);
    if (_ownsController) _controller.dispose();
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _shouldAutoScroll =
        _scrollController.position.extentAfter <=
        widget.configuration.scrollThreshold;
    for (final entry in _pendingVisibleItems.entries) {
      _checkVisibleAfterFrame(
        entry.key,
        entry.value.request,
        entry.value.context,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    if (_bottomInset != null &&
        bottomInset > _bottomInset! &&
        _shouldAutoScroll) {
      _scheduleScroll(force: true);
    }
    _bottomInset = bottomInset;
  }

  void _onStateChanged() {
    if (!mounted) return;
    if (_controller.state.messages.isEmpty) {
      _messageWidgets.clear();
      _seenMessages.clear();
      _pendingVisibleItems.clear();
    }
    setState(() {});
    _scheduleScroll();
  }

  void _scheduleScroll({bool force = false}) {
    if (!_shouldAutoScroll || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      if (!_shouldAutoScroll && !force) {
        _checkPendingVisibleText();
        return;
      }
      final previousOffset = _scrollController.position.pixels;
      final target = _scrollController.position.maxScrollExtent;
      if (_controller.state.isTyping ||
          MediaQuery.disableAnimationsOf(context) ||
          _theme.animationDuration == Duration.zero) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: _theme.animationDuration,
          curve: Curves.easeOut,
        );
      }
      if (_scrollController.position.pixels == previousOffset) {
        _checkPendingVisibleText();
      }
    });
  }

  void _checkPendingVisibleText() {
    for (final entry in _pendingVisibleItems.entries.toList(growable: false)) {
      _recordVisibleTextIfPainted(
        entry.key,
        entry.value.request,
        entry.value.context,
      );
    }
  }

  void _checkVisibleAfterFrame(
    String messageId,
    int requestNumber,
    BuildContext contentContext,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recordVisibleTextIfPainted(messageId, requestNumber, contentContext);
    });
  }

  void _recordVisibleTextIfPainted(
    String messageId,
    int requestNumber,
    BuildContext contentContext,
  ) {
    if (!mounted) return;
    final pending = _pendingVisibleItems[messageId];
    if (pending?.request != requestNumber ||
        pending?.context != contentContext) {
      return;
    }
    if (!contentContext.mounted) {
      _pendingVisibleItems.remove(messageId);
      return;
    }
    final content = contentContext.findRenderObject();
    if (content is! RenderBox || !content.attached || !content.hasSize) return;
    final viewport = switch (RenderAbstractViewport.of(content)) {
      RenderBox box => box,
      _ => null,
    };
    if (viewport == null || !viewport.attached || !viewport.hasSize) return;
    final contentBounds = MatrixUtils.transformRect(
      content.getTransformTo(viewport),
      Offset.zero & content.size,
    );
    if (!(Offset.zero & viewport.size).overlaps(contentBounds)) return;
    _controller.recordFirstRenderedText(
      messageId,
      requestNumber: requestNumber,
    );
    _pendingVisibleItems.remove(messageId);
  }

  void _watchFirstVisibleText(
    String messageId,
    int requestNumber,
    BuildContext contentContext,
  ) {
    if (_controller.pendingRenderedRequestNumber(messageId) != requestNumber) {
      return;
    }
    _pendingVisibleItems[messageId] = (
      request: requestNumber,
      context: contentContext,
    );
    // The existing auto-scroll can run after this frame; observe the next one.
    if (_scrollScheduled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && contentContext.mounted) {
          _checkVisibleAfterFrame(messageId, requestNumber, contentContext);
        }
      });
    } else {
      _checkVisibleAfterFrame(messageId, requestNumber, contentContext);
    }
  }

  Widget _messageAt(ChatMessage message, {required bool isLatestAssistant}) {
    final pendingRequestNumber = _controller.pendingRenderedRequestNumber(
      message.id,
    );
    final showRegenerateAction =
        widget.configuration.showRegenerateAction && isLatestAssistant;
    final existing = _messageWidgets[message.id];
    if (existing != null &&
        identical(existing.message, message) &&
        identical(existing.theme, _theme) &&
        existing.showSources == widget.configuration.showLocalSources &&
        existing.showGenerationTime ==
            widget.configuration.showGenerationTime &&
        existing.showCopyAction == widget.configuration.showCopyAction &&
        existing.showRegenerateAction == showRegenerateAction &&
        existing.showRetryAction == widget.configuration.showRetryAction &&
        existing.retryEnabled ==
            (_controller.state.canSend && !_isRunningEvaluation) &&
        existing.regenerateEnabled ==
            (_controller.state.canSend && !_isRunningEvaluation) &&
        existing.generationTimeLabel ==
            widget.configuration.generationTimeLabel &&
        existing.assistantName == widget.configuration.assistantName &&
        existing.assistantAvatar == widget.configuration.assistantAvatar &&
        existing.sourceSectionLabel ==
            widget.configuration.sourceSectionLabel) {
      return existing;
    }
    return _messageWidgets[message.id] = _ChatBubble(
      key: ValueKey(message.id),
      message: message,
      theme: _theme,
      showSources: widget.configuration.showLocalSources,
      showGenerationTime: widget.configuration.showGenerationTime,
      showCopyAction: widget.configuration.showCopyAction,
      showRegenerateAction: showRegenerateAction,
      showRetryAction: widget.configuration.showRetryAction,
      retryEnabled: _controller.state.canSend && !_isRunningEvaluation,
      regenerateEnabled: _controller.state.canSend && !_isRunningEvaluation,
      generationTimeLabel: widget.configuration.generationTimeLabel,
      assistantName: widget.configuration.assistantName,
      assistantAvatar: widget.configuration.assistantAvatar,
      sourceSectionLabel: widget.configuration.sourceSectionLabel,
      seenMessages: _seenMessages,
      onFirstVisibleText:
          pendingRequestNumber == null ||
              message.author != ChatAuthor.assistant ||
              message.text.trim().isEmpty
          ? null
          : (contentContext) => _watchFirstVisibleText(
              message.id,
              pendingRequestNumber,
              contentContext,
            ),
      onRetry: () => _retry(message),
      onRegenerate: () => _regenerate(message),
    );
  }

  Future<void> _regenerate(ChatMessage message) async {
    final error = await _controller.regenerate(message);
    if (mounted && error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _retry(ChatMessage message) {
    if (!_controller.state.canSend || _isRunningEvaluation) return;
    _controller.retry(message);
  }

  void _send() {
    final text = _composerController.text;
    if (_isRunningEvaluation ||
        !_controller.state.canSend ||
        text.trim().isEmpty) {
      return;
    }
    _composerController.clear();
    _controller.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final chatTheme = _theme;
    final hostTheme = Theme.of(context);
    return Theme(
      data: hostTheme.copyWith(
        colorScheme: hostTheme.colorScheme.copyWith(
          primary: chatTheme.primaryColor,
          onPrimary: chatTheme.primaryTextColor,
          secondary: chatTheme.accentColor,
        ),
      ),
      child: Scaffold(
        backgroundColor: chatTheme.backgroundColor,
        appBar: AppBar(
          title: Text(widget.configuration.title),
          backgroundColor: chatTheme.surfaceColor,
          foregroundColor: chatTheme.surfaceTextColor,
          actions: [
            IconButton(
              tooltip: 'Clear conversation',
              onPressed: state.messages.isEmpty || state.isTyping
                  ? null
                  : _controller.clearHistory,
              icon: const Icon(Icons.delete_outline),
            ),
            if (kDebugMode && widget.chatIntentEvaluationRunner != null)
              IconButton(
                tooltip: 'Run routing evaluation',
                onPressed:
                    state.modelState.status != ModelStatus.ready ||
                        state.isTyping ||
                        _isRunningEvaluation
                    ? null
                    : _runRoutingEvaluation,
                icon: const Icon(Icons.alt_route),
              ),
            if (kDebugMode && widget.retrievalEvaluationRunner != null)
              IconButton(
                tooltip: 'Run retrieval evaluation',
                onPressed:
                    state.modelState.status != ModelStatus.ready ||
                        state.isTyping ||
                        _isRunningEvaluation
                    ? null
                    : _runEvaluation,
                icon: const Icon(Icons.analytics_outlined),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _ModelStatusBanner(
                state: state.modelState,
                theme: chatTheme,
                showRetryAction: widget.configuration.showRetryAction,
                onRetry: _controller.retryModelInitialization,
              ),
              if (state.isPreparingKnowledge || state.knowledgeError != null)
                _KnowledgeStatusBanner(state: state, theme: chatTheme),
              Expanded(
                child: state.messages.isEmpty
                    ? _Welcome(
                        configuration: widget.configuration,
                        theme: chatTheme,
                        enabled: state.canSend && !_isRunningEvaluation,
                        onSuggestion: (value) {
                          _composerController.text = value;
                          _send();
                        },
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.symmetric(
                          horizontal: chatTheme.spacing,
                          vertical: chatTheme.spacing,
                        ),
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) => Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: _messageAt(
                              state.messages[index],
                              isLatestAssistant:
                                  index == state.messages.length - 1 &&
                                  state.messages[index].author ==
                                      ChatAuthor.assistant,
                            ),
                          ),
                        ),
                      ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _Composer(
                    controller: _composerController,
                    enabled: state.canSend && !_isRunningEvaluation,
                    onSend: _send,
                    theme: chatTheme,
                    modelLabel: widget.configuration.showModelLabel
                        ? widget.configuration.modelLabel
                        : null,
                    runtimeBackend:
                        state.modelState.status == ModelStatus.ready &&
                            widget.configuration.showRuntimeBackend
                        ? widget.runtimeBackendLabel?.call()
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runRoutingEvaluation() async {
    final runner = widget.chatIntentEvaluationRunner;
    if (runner == null || _isRunningEvaluation || _controller.state.isTyping) {
      return;
    }
    setState(() => _isRunningEvaluation = true);
    try {
      final summary = await runner.run();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Routing: ${summary.passedCaseCount}/${summary.totalCases} correct, '
            'Accuracy ${(summary.accuracy * 100).toStringAsFixed(0)}%, '
            'Avg ${summary.averageLatency.inMilliseconds}ms, '
            'Max ${summary.maxLatency.inMilliseconds}ms',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isRunningEvaluation = false);
    }
  }

  Future<void> _runEvaluation() async {
    final runner = widget.retrievalEvaluationRunner;
    if (runner == null || _isRunningEvaluation || _controller.state.isTyping) {
      return;
    }
    setState(() => _isRunningEvaluation = true);
    try {
      final summary = await runner.run();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Retrieval: ${summary.passedCaseCount}/${summary.expectedMatchCaseCount} '
            'matches, Hit Rate@3 ${(summary.hitRateAt3 * 100).toStringAsFixed(0)}%',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isRunningEvaluation = false);
    }
  }
}

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

class _ModelStatusBanner extends StatelessWidget {
  const _ModelStatusBanner({
    required this.state,
    required this.theme,
    required this.showRetryAction,
    required this.onRetry,
  });

  final ModelState state;
  final AiChatTheme theme;
  final bool showRetryAction;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.status == ModelStatus.ready) return const SizedBox.shrink();
    final message = switch (state.status) {
      ModelStatus.notDownloaded => 'Preparing local AI model…',
      ModelStatus.downloading =>
        'Downloading local AI model${state.downloadProgress == null ? '' : ': ${state.downloadProgress}%'}',
      ModelStatus.downloaded ||
      ModelStatus.loading => 'Loading local AI model…',
      ModelStatus.error =>
        'Local AI model could not be loaded. Please try again.',
      ModelStatus.ready => '',
    };
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        width: double.infinity,
        color: theme.primaryColor.withValues(alpha: .10),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: TextStyle(color: theme.backgroundTextColor)),
            if (state.status == ModelStatus.error && showRetryAction)
              TextButton.icon(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: theme.primaryColor,
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry model loading'),
              ),
            if (state.status == ModelStatus.downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                color: theme.primaryColor,
                value: state.downloadProgress == null
                    ? null
                    : state.downloadProgress! / 100,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KnowledgeStatusBanner extends StatelessWidget {
  const _KnowledgeStatusBanner({required this.state, required this.theme});

  final ChatState state;
  final AiChatTheme theme;

  @override
  Widget build(BuildContext context) {
    final message =
        state.knowledgeError ??
        'Preparing local knowledge for private, offline answers…';
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        width: double.infinity,
        color: theme.primaryColor.withValues(alpha: .10),
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: TextStyle(color: theme.backgroundTextColor),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({
    required this.configuration,
    required this.theme,
    required this.enabled,
    required this.onSuggestion,
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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
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
          if (!isUser) ...[
            AiAvatar(
              theme: theme,
              assistantName: assistantName,
              assistantAvatar: assistantAvatar,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: isUser ? 'Your message' : 'Assistant message',
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: theme.spacing,
                      vertical: theme.spacing * .75,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? theme.userBubbleColor
                          : theme.assistantBubbleColor,
                      borderRadius: BorderRadius.circular(theme.bubbleRadius),
                      border: Border.all(
                        color: message.isError
                            ? theme.primaryColor.withValues(alpha: .65)
                            : theme.borderColor,
                      ),
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
                    padding: EdgeInsets.only(top: theme.spacing * .4),
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
            '$label \u00B7 ${sources.length}',
            style: textTheme.bodySmall?.copyWith(color: metadataColor),
          ),
          SizedBox(height: theme.spacing * .25),
          for (final source in sources)
            Padding(
              padding: EdgeInsets.only(bottom: theme.spacing * .25),
              child: Text(switch (source.metadata['code']) {
                final String code when code.trim().isNotEmpty =>
                  '${code.trim()} \u2014 ${source.title}',
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
            const SizedBox(width: 6),
            Text(
              'Thinking…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: widget.theme.assistantTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.theme,
    required this.modelLabel,
    required this.runtimeBackend,
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
                    : '$modelLabel \u00B7 $runtimeBackend',
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
