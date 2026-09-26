import 'package:flutter/material.dart';

/// White-label visual styling for the chat experience.
@immutable
class AiChatTheme {
  const AiChatTheme({
    Color? primaryColor,
    Color? accentColor,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? userBubbleColor,
    Color? assistantBubbleColor,
    Color? userTextColor,
    Color? assistantTextColor,
    Color? borderColor,
    Color? inputBackgroundColor,
    this.avatarLabel = 'AI',
    this.avatarIcon = Icons.auto_awesome,
    this.bubbleRadius = 18,
    this.spacing = 16,
    this.animationDuration = const Duration(milliseconds: 180),
  }) : _primaryColor = primaryColor,
       _accentColor = accentColor,
       _backgroundColor = backgroundColor,
       _surfaceColor = surfaceColor,
       _userBubbleColor = userBubbleColor,
       _assistantBubbleColor = assistantBubbleColor,
       _userTextColor = userTextColor,
       _assistantTextColor = assistantTextColor,
       _borderColor = borderColor,
       _inputBackgroundColor = inputBackgroundColor;

  final Color? _primaryColor;
  final Color? _accentColor;
  final Color? _backgroundColor;
  final Color? _surfaceColor;
  final Color? _userBubbleColor;
  final Color? _assistantBubbleColor;
  final Color? _userTextColor;
  final Color? _assistantTextColor;
  final Color? _borderColor;
  final Color? _inputBackgroundColor;

  Color get primaryColor => _primaryColor ?? const Color(0xFF3F51B5);
  Color get accentColor => _accentColor ?? const Color(0xFF00A8A8);
  Color get backgroundColor => _backgroundColor ?? const Color(0xFFF9FAFF);
  Color get surfaceColor => _surfaceColor ?? Colors.white;
  Color get userBubbleColor => _userBubbleColor ?? primaryColor;
  Color get assistantBubbleColor =>
      _assistantBubbleColor ?? const Color(0xFFF1F3F8);
  Color get primaryTextColor => _readableOn(primaryColor);
  Color get userTextColor => _userTextColor ?? _readableOn(userBubbleColor);
  Color get assistantTextColor =>
      _assistantTextColor ?? _readableOn(assistantBubbleColor);
  Color get surfaceTextColor => _readableOn(surfaceColor);
  Color get backgroundTextColor => _readableOn(backgroundColor);
  Color get inputTextColor => _readableOn(inputBackgroundColor);
  Color get borderColor => _borderColor ?? const Color(0xFFD7DBE8);
  Color get inputBackgroundColor => _inputBackgroundColor ?? Colors.white;

  static Color _readableOn(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : const Color(0xFF1A1C20);

  /// Uses the host's dark palette for colors the consumer has not overridden.
  AiChatTheme resolve(ColorScheme colorScheme) {
    if (colorScheme.brightness != Brightness.dark) return this;
    return AiChatTheme(
      primaryColor: _primaryColor ?? colorScheme.primary,
      accentColor: _accentColor ?? colorScheme.secondary,
      backgroundColor: _backgroundColor ?? colorScheme.surface,
      surfaceColor: _surfaceColor ?? colorScheme.surface,
      userBubbleColor: _userBubbleColor,
      assistantBubbleColor:
          _assistantBubbleColor ?? colorScheme.surfaceContainerHighest,
      userTextColor: _userTextColor,
      assistantTextColor: _assistantTextColor,
      borderColor: _borderColor ?? colorScheme.outlineVariant,
      inputBackgroundColor: _inputBackgroundColor ?? colorScheme.surface,
      avatarLabel: avatarLabel,
      avatarIcon: avatarIcon,
      bubbleRadius: bubbleRadius,
      spacing: spacing,
      animationDuration: animationDuration,
    );
  }

  final String avatarLabel;
  final IconData avatarIcon;
  final double bubbleRadius;
  final double spacing;
  final Duration animationDuration;
}

/// White-label chat text and UI behavior shared by the app and chat feature.
@immutable
class AiChatConfiguration {
  const AiChatConfiguration({
    this.title = 'Offline Assistant',
    this.assistantName = 'ViGuide AI',
    this.assistantAvatar,
    this.welcomeTitle = 'How can I help?',
    this.welcomeMessage = 'Ask a question using your local knowledge base.',
    this.greetingMessage = 'Hi! How can I help you today?',
    this.wellbeingMessage =
        "I'm doing well and ready to help with your technical questions.",
    this.gratitudeMessage = "You're welcome!",
    this.unsupportedQuestionMessage =
        "I'm an AI assistant designed to help with technical information "
        "available in my knowledge base. I can't answer that question.",
    this.suggestions = const [
      'What does error E123 mean?',
      'How do I troubleshoot a network connection?',
    ],
    this.showLocalSources = true,
    this.sourceSectionLabel = 'Sources',
    this.modelLabel = 'Qwen3 0.6B \u00B7 Local',
    this.showModelLabel = true,
    this.showRuntimeBackend = true,
    this.showGenerationTime = true,
    this.generationTimeLabel = 'Generated in',
    this.showCopyAction = true,
    this.showRegenerateAction = true,
    this.showRetryAction = true,
    this.scrollThreshold = 160,
    this.maxHistoryMessages = 6,
  });

  final String title;
  final String assistantName;
  final ImageProvider? assistantAvatar;
  final String welcomeTitle;
  final String welcomeMessage;
  final String greetingMessage;
  final String wellbeingMessage;
  final String gratitudeMessage;
  final String unsupportedQuestionMessage;
  final List<String> suggestions;
  final bool showLocalSources;
  final String sourceSectionLabel;
  final String modelLabel;
  final bool showModelLabel;
  final bool showRuntimeBackend;
  final bool showGenerationTime;
  final String generationTimeLabel;
  final bool showCopyAction;
  final bool showRegenerateAction;
  final bool showRetryAction;
  final double scrollThreshold;
  final int maxHistoryMessages;
}
