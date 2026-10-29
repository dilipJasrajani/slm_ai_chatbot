import 'package:flutter/material.dart';

/// White-label visual styling for the chat experience.
@immutable
class AiChatTheme {
  static const brandColor = Color(0xFFFFE4DF);
  static const brandDark = Color(0xFFCC2C08);
  static const white = Color(0xFFFFFFFF);
  static const background = Color(0xFFF3F1F1);
  static const textPrimary = Color(0xFF101314);
  static const textSecondary = Color(0xFF6D7276);
  static const error = Color(0xFFCC2C08);
  static const warning = Color(0xFFFFB000);
  static const button = Color(0xFFCC2C08);

  const AiChatTheme({
    Color? primaryColor,
    Color? buttonColor,
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
       _buttonColor = buttonColor,
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
  final Color? _buttonColor;
  final Color? _accentColor;
  final Color? _backgroundColor;
  final Color? _surfaceColor;
  final Color? _userBubbleColor;
  final Color? _assistantBubbleColor;
  final Color? _userTextColor;
  final Color? _assistantTextColor;
  final Color? _borderColor;
  final Color? _inputBackgroundColor;

  Color get buttonColor =>
      _buttonColor ?? (_primaryColor == null ? button : primaryColor);
  Color get buttonTextColor => _readableOn(buttonColor);
  Color get primaryColor => _primaryColor ?? brandColor;
  Color get accentColor => _accentColor ?? brandDark;
  Color get backgroundColor => _backgroundColor ?? background;
  Color get surfaceColor => _surfaceColor ?? white;
  Color get userBubbleColor => _userBubbleColor ?? accentColor;
  Color get assistantBubbleColor => _assistantBubbleColor ?? surfaceColor;
  Color get primaryTextColor => _readableOn(primaryColor);
  Color get userTextColor => _userTextColor ?? _readableOn(userBubbleColor);
  Color get assistantTextColor =>
      _assistantTextColor ?? _readableOn(backgroundColor);
  Color get surfaceTextColor => _readableOn(surfaceColor);
  Color get backgroundTextColor => _readableOn(backgroundColor);
  Color get secondaryTextColor =>
      ThemeData.estimateBrightnessForColor(backgroundColor) == Brightness.dark
      ? backgroundTextColor.withValues(alpha: .75)
      : textSecondary;
  Color get inputTextColor => _readableOn(inputBackgroundColor);
  Color get borderColor => _borderColor ?? textSecondary.withValues(alpha: .35);
  Color get inputBackgroundColor => _inputBackgroundColor ?? white;

  static Color _readableOn(Color background) =>
      background.computeLuminance() < .179 ? white : textPrimary;

  /// Uses the host's dark palette for colors the consumer has not overridden.
  AiChatTheme resolve(ColorScheme colorScheme) {
    if (colorScheme.brightness != Brightness.dark) return this;
    return AiChatTheme(
      primaryColor: _primaryColor ?? colorScheme.primary,
      buttonColor:
          _buttonColor ?? (_primaryColor == null ? colorScheme.primary : null),
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
    this.title = 'ViSage AI',
    this.assistantName = 'ViSage AI',
    this.assistantAvatar = const AssetImage('assets/icons/dumbledore-48.png'),
    this.welcomeTitle = '',
    this.welcomeMessage = 'Ask a question using your local knowledge base.',
    this.greetingMessage = 'Hi! How can I help you today?',
    this.wellbeingMessage =
        "I'm doing well and ready to help with your technical questions.",
    this.gratitudeMessage = "You're welcome!",
    this.unsupportedQuestionMessage =
        "I'm an AI assistant designed to help with technical information "
        "available in my knowledge base. I can't answer that question.",
    this.suggestions = const [
      'What does error F.867 mean?',
      'How do I troubleshoot a Communication error PlusBus?',
    ],
    this.showLocalSources = false,
    this.sourceSectionLabel = 'Sources',
    this.modelLabel = 'Qwen3 0.6B \u00B7 Local',
    this.showModelLabel = true,
    this.showRuntimeBackend = true,
    this.showGenerationTime = true,
    this.generationTimeLabel = '',
    this.showCopyAction = true,
    this.showRegenerateAction = true,
    this.showRetryAction = true,
    this.scrollThreshold = 160,
    this.maxHistoryMessages = 4,
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
