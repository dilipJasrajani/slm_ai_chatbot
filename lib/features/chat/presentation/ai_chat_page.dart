import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:slm_ai_chatbot/features/chat/evaluation/domain/chat_intent_evaluation_runner.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_manager.dart';
import 'package:slm_ai_chatbot/features/model/domain/model_status.dart';
import 'package:slm_ai_chatbot/features/rag/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/rag/evaluation/domain/retrieval_evaluation_runner.dart';
import 'chat_controller.dart';
import 'chat_models.dart';

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

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  late final ChatController _controller;
  late final bool _ownsController;
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
  var _shouldAutoScroll = true;
  var _isRunningEvaluation = false;

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
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
    if (_shouldAutoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients || !_shouldAutoScroll) {
          return;
        }
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
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
    return Scaffold(
      backgroundColor: widget.chatTheme.backgroundColor,
      appBar: AppBar(
        title: Text(widget.configuration.title),
        backgroundColor: widget.chatTheme.surfaceColor,
        foregroundColor: widget.chatTheme.assistantTextColor,
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
              color: widget.chatTheme.primaryColor,
            ),
            if (state.isPreparingKnowledge || state.knowledgeError != null)
              _KnowledgeStatusBanner(
                state: state,
                color: widget.chatTheme.primaryColor,
              ),
            Expanded(
              child: state.messages.isEmpty
                  ? _Welcome(
                      configuration: widget.configuration,
                      theme: widget.chatTheme,
                      onSuggestion: (value) {
                        _composerController.text = value;
                        _send();
                      },
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.all(widget.chatTheme.spacing),
                      itemCount: state.messages.length,
                      itemBuilder: (context, index) => _ChatBubble(
                        message: state.messages[index],
                        theme: widget.chatTheme,
                        showSources: widget.configuration.showLocalSources,
                        onRetry: () => _controller.retry(state.messages[index]),
                      ),
                    ),
            ),
            if (state.isTyping)
              _TypingIndicator(theme: widget.chatTheme)
            else
              const SizedBox(height: 8),
            _Composer(
              controller: _composerController,
              enabled: state.canSend && !_isRunningEvaluation,
              onSend: _send,
              theme: widget.chatTheme,
            ),
          ],
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
  const AiAvatar({required this.theme, super.key});

  final AiChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${theme.avatarLabel} assistant',
      child: CircleAvatar(
        backgroundColor: theme.primaryColor,
        child: Icon(theme.avatarIcon, color: theme.userTextColor),
      ),
    );
  }
}

class _ModelStatusBanner extends StatelessWidget {
  const _ModelStatusBanner({required this.state, required this.color});

  final ModelState state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (state.status == ModelStatus.ready) return const SizedBox.shrink();
    final message = switch (state.status) {
      ModelStatus.notDownloaded => 'Preparing local AI model…',
      ModelStatus.downloading =>
        'Downloading local AI model${state.downloadProgress == null ? '' : ': ${state.downloadProgress}%'}',
      ModelStatus.downloaded ||
      ModelStatus.loading => 'Loading local AI model…',
      ModelStatus.error => 'Model unavailable: ${state.errorMessage}',
      ModelStatus.ready => '',
    };
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        width: double.infinity,
        color: color.withValues(alpha: .10),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (state.status == ModelStatus.downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
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
  const _KnowledgeStatusBanner({required this.state, required this.color});

  final ChatState state;
  final Color color;

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
        color: color.withValues(alpha: .10),
        padding: const EdgeInsets.all(12),
        child: Text(message),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({
    required this.configuration,
    required this.theme,
    required this.onSuggestion,
  });

  final AiChatConfiguration configuration;
  final AiChatTheme theme;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AiAvatar(theme: theme),
            const SizedBox(height: 16),
            Text(
              configuration.welcomeTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(configuration.welcomeMessage, textAlign: TextAlign.center),
            if (configuration.suggestions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: configuration.suggestions
                    .map(
                      (suggestion) => ActionChip(
                        label: Text(suggestion),
                        onPressed: () => onSuggestion(suggestion),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
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
    required this.onRetry,
  });

  final ChatMessage message;
  final AiChatTheme theme;
  final bool showSources;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isUser = message.author == ChatAuthor.user;
    final textColor = isUser ? theme.userTextColor : theme.assistantTextColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[AiAvatar(theme: theme), const SizedBox(width: 8)],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: isUser ? 'Your message' : 'Assistant message',
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? theme.userBubbleColor
                          : theme.assistantBubbleColor,
                      borderRadius: BorderRadius.circular(theme.bubbleRadius),
                      border: Border.all(color: theme.borderColor),
                    ),
                    child: message.isStreaming && message.text.isEmpty
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            message.text,
                            style: TextStyle(color: textColor),
                          ),
                  ),
                ),
                if (showSources && message.sourceTitles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Local sources: ${message.sourceTitles.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (message.isError)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
              ],
            ),
          ),
        ],
      ),
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
    duration: const Duration(milliseconds: 650),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animationController,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            AiAvatar(theme: widget.theme),
            const SizedBox(width: 8),
            const Text('Thinking…'),
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
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  final AiChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(theme.spacing * .75),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                labelText: 'Ask a question',
                filled: true,
                fillColor: theme.inputBackgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(theme.bubbleRadius),
                  borderSide: BorderSide(color: theme.borderColor),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send message',
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
