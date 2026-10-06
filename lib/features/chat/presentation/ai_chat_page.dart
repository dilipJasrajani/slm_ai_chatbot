import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show MatrixUtils, RenderAbstractViewport;

import 'package:slm_ai_chatbot/features/chat/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/chat/evaluation/domain/chat_intent_evaluation_runner.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_manager.dart';
import 'package:slm_ai_chatbot/features/model/domain/model_status.dart';
import 'package:slm_ai_chatbot/features/rag/evaluation/domain/retrieval_evaluation_runner.dart';

import 'ai_chat_configuration.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/chat_status_banners.dart';
import 'widgets/chat_welcome.dart';

export 'widgets/ai_avatar.dart';

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
  /// Creates the state object that coordinates this chat screen.
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  late final ChatController _controller;
  late final bool _ownsController;
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
  final _messageWidgets = <String, ChatMessageBubble>{};
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

  /// Resolves the configured theme once per source theme and color scheme.
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
  /// Creates or adopts the chat controller, then observes state and scrolling.
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
  /// Releases page-owned controllers and stops observing transient UI state.
  void dispose() {
    _pendingVisibleItems.clear();
    _controller.removeListener(_onStateChanged);
    if (_ownsController) _controller.dispose();
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  /// Keeps the newest content visible when the keyboard opens during a chat.
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

  /// Rebuilds for controller updates and resets transient message state on clear.
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

  /// Tracks whether the user remains close enough to the bottom to auto-scroll.
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

  /// Scrolls after the current frame while preserving the user's reading position.
  void _scheduleScroll({bool force = false}) {
    if (!_shouldAutoScroll || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
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

  /// Rechecks every pending assistant response after scrolling or layout changes.
  void _checkPendingVisibleText() {
    for (final entry in _pendingVisibleItems.entries.toList(growable: false)) {
      _recordVisibleTextIfPainted(
        entry.key,
        entry.value.request,
        entry.value.context,
      );
    }
  }

  /// Defers a visibility measurement until the assistant content has been laid out.
  void _checkVisibleAfterFrame(
    String messageId,
    int requestNumber,
    BuildContext contentContext,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recordVisibleTextIfPainted(messageId, requestNumber, contentContext);
    });
  }

  /// Records latency when pending assistant text first overlaps the chat viewport.
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

  /// Starts observing a streamed response until its first text becomes visible.
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

  /// Returns a cached message widget or creates one with current display options.
  Widget _messageAt(ChatMessage message, {required bool isLatestAssistant}) {
    final pendingRequestNumber = _controller.pendingRenderedRequestNumber(
      message.id,
    );
    final showRegenerateAction =
        widget.configuration.showRegenerateAction && isLatestAssistant;
    final interactionEnabled =
        _controller.state.canSend && !_isRunningEvaluation;
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
        existing.retryEnabled == interactionEnabled &&
        existing.regenerateEnabled == interactionEnabled &&
        existing.generationTimeLabel ==
            widget.configuration.generationTimeLabel &&
        existing.assistantName == widget.configuration.assistantName &&
        existing.assistantAvatar == widget.configuration.assistantAvatar &&
        existing.sourceSectionLabel ==
            widget.configuration.sourceSectionLabel) {
      return existing;
    }
    return _messageWidgets[message.id] = ChatMessageBubble(
      key: ValueKey(message.id),
      message: message,
      theme: _theme,
      showSources: widget.configuration.showLocalSources,
      showGenerationTime: widget.configuration.showGenerationTime,
      showCopyAction: widget.configuration.showCopyAction,
      showRegenerateAction: showRegenerateAction,
      showRetryAction: widget.configuration.showRetryAction,
      retryEnabled: interactionEnabled,
      regenerateEnabled: interactionEnabled,
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

  /// Sends the current composer text when chat input is currently available.
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

  /// Restarts a failed assistant response when chat input is currently available.
  void _retry(ChatMessage message) {
    if (!_controller.state.canSend || _isRunningEvaluation) return;
    _controller.retry(message);
  }

  /// Regenerates an assistant response and surfaces any restoration error.
  Future<void> _regenerate(ChatMessage message) async {
    final error = await _controller.regenerate(message);
    if (mounted && error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  /// Composes the app bar, status banners, conversation content, and composer.
  Widget build(BuildContext context) {
    final state = _controller.state;
    final chatTheme = _theme;
    final hostTheme = Theme.of(context);
    final interactionEnabled = state.canSend && !_isRunningEvaluation;
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
              ModelStatusBanner(
                state: state.modelState,
                theme: chatTheme,
                showRetryAction: widget.configuration.showRetryAction,
                onRetry: _controller.retryModelInitialization,
              ),
              if (state.isPreparingKnowledge || state.knowledgeError != null)
                KnowledgeStatusBanner(state: state, theme: chatTheme),
              Expanded(
                child: state.messages.isEmpty
                    ? ChatWelcome(
                        configuration: widget.configuration,
                        theme: chatTheme,
                        enabled: interactionEnabled,
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
                  child: ChatComposer(
                    controller: _composerController,
                    enabled: interactionEnabled,
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

  /// Runs debug-only CHAT-versus-KNOWLEDGE routing evaluation and shows its summary.
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

  /// Runs debug-only retrieval evaluation and shows its result summary.
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
