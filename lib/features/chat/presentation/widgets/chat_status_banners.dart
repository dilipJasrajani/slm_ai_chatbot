import 'package:flutter/material.dart';

import 'package:slm_ai_chatbot/features/model/domain/model_status.dart';

import '../ai_chat_configuration.dart';
import '../chat_models.dart';

/// Shows local model installation, loading, and failure state.
class ModelStatusBanner extends StatelessWidget {
  const ModelStatusBanner({
    required this.state,
    required this.theme,
    required this.showRetryAction,
    required this.onRetry,
    super.key,
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
        'Installing local AI model${state.downloadProgress == null ? '' : ': ${state.downloadProgress}%'}',
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

/// Shows preparation status for the local knowledge base.
class KnowledgeStatusBanner extends StatelessWidget {
  const KnowledgeStatusBanner({
    required this.state,
    required this.theme,
    super.key,
  });

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
