import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'ai_chat_configuration.dart';

/// Renders completed assistant content without changing its original text.
class AssistantContent extends StatelessWidget {
  const AssistantContent({required this.text, required this.theme, super.key});

  final String text;
  final AiChatTheme theme;

  static final _blockSyntax = RegExp(
    r'(^|\n) {0,3}(?:#{1,6} |[-+*] |\d+[.)] |> |```|~~~)',
  );

  @override
  Widget build(BuildContext context) {
    final hostTheme = Theme.of(context);
    final body = hostTheme.textTheme.bodyMedium?.copyWith(
      color: theme.assistantTextColor,
      height: 1.4,
    );
    // Keep simple answers as Text; only parse answers with Markdown structure.
    if (!text.contains('\n\n') &&
        !text.contains('`') &&
        !text.contains('**') &&
        !text.contains('__') &&
        !text.contains('[') &&
        !_blockSyntax.hasMatch(text)) {
      return Text(text, style: body);
    }

    final codeText = hostTheme.textTheme.bodyMedium?.copyWith(
      color: theme.surfaceTextColor,
      fontFamily: 'monospace',
      height: 1.4,
    );
    return MarkdownBody(
      data: text,
      imageBuilder: (uri, title, alt) =>
          Text(alt == null || alt.isEmpty ? 'Image' : alt, style: body),
      builders: {'pre': _CodeBlockBuilder(theme: theme, codeStyle: codeText)},
      styleSheet: MarkdownStyleSheet.fromTheme(hostTheme).copyWith(
        p: body,
        a: body?.copyWith(decoration: TextDecoration.underline),
        h1: hostTheme.textTheme.headlineSmall?.copyWith(
          color: theme.assistantTextColor,
        ),
        h2: hostTheme.textTheme.titleLarge?.copyWith(
          color: theme.assistantTextColor,
        ),
        h3: hostTheme.textTheme.titleMedium?.copyWith(
          color: theme.assistantTextColor,
        ),
        h4: hostTheme.textTheme.bodyLarge?.copyWith(
          color: theme.assistantTextColor,
          fontWeight: FontWeight.bold,
        ),
        h5: body?.copyWith(fontWeight: FontWeight.bold),
        h6: body?.copyWith(fontWeight: FontWeight.bold),
        code: codeText?.copyWith(backgroundColor: theme.surfaceColor),
        listBullet: body,
        blockquote: body?.copyWith(color: theme.surfaceTextColor),
        blockquoteDecoration: BoxDecoration(
          color: theme.surfaceColor,
          border: Border(left: BorderSide(color: theme.borderColor, width: 3)),
        ),
        tableHead: body?.copyWith(fontWeight: FontWeight.bold),
        tableBody: body,
        img: body,
        blockSpacing: theme.spacing * .65,
        codeblockDecoration: BoxDecoration(
          color: theme.surfaceColor,
          border: Border.all(color: theme.borderColor),
          borderRadius: BorderRadius.circular(theme.bubbleRadius * .5),
        ),
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({required this.theme, required this.codeStyle});

  final AiChatTheme theme;
  final TextStyle? codeStyle;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.children case [
      md.Element codeElement,
      ...,
    ] when codeElement.tag == 'code') {
      // The Markdown parser adds one terminal newline to fenced code.
      final parsedCode = codeElement.textContent;
      final code = parsedCode.endsWith('\n')
          ? parsedCode.substring(0, parsedCode.length - 1)
          : parsedCode;
      final codeClass = codeElement.attributes['class'];
      final language = codeClass != null && codeClass.startsWith('language-')
          ? codeClass.substring('language-'.length)
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: theme.spacing * .75,
              right: theme.spacing * .25,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language == null || language.isEmpty ? 'Code' : language,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: theme.surfaceTextColor,
                    ),
                  ),
                ),
                CopyTextAction(text: code, theme: theme, codeBlock: true),
              ],
            ),
          ),
          Divider(height: 1, color: theme.borderColor),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.all(theme.spacing * .75),
            child: Text(code, softWrap: false, style: codeStyle),
          ),
        ],
      );
    }
    return null;
  }
}

/// Copies the original response or the raw contents of one code block.
class CopyTextAction extends StatefulWidget {
  const CopyTextAction({
    required this.text,
    required this.theme,
    this.codeBlock = false,
    super.key,
  });

  final String text;
  final AiChatTheme theme;
  final bool codeBlock;

  @override
  State<CopyTextAction> createState() => _CopyTextActionState();
}

class _CopyTextActionState extends State<CopyTextAction> {
  Timer? _feedbackTimer;
  bool _copied = false;
  bool _copyFailed = false;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
    } on PlatformException {
      _showFeedback(copied: false);
      return;
    } on MissingPluginException {
      _showFeedback(copied: false);
      return;
    }
    _showFeedback(copied: true);
  }

  void _showFeedback({required bool copied}) {
    if (!mounted) return;
    _feedbackTimer?.cancel();
    setState(() {
      _copied = copied;
      _copyFailed = !copied;
    });
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _copied = false;
          _copyFailed = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(CopyTextAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _feedbackTimer?.cancel();
      _copied = false;
      _copyFailed = false;
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = _copied
        ? Icons.check
        : _copyFailed
        ? Icons.error_outline
        : Icons.copy_outlined;
    if (widget.codeBlock) {
      return Tooltip(
        message: _copied
            ? 'Code copied'
            : _copyFailed
            ? 'Copy code failed'
            : 'Copy code',
        child: TextButton.icon(
          onPressed: _copy,
          icon: Icon(icon, size: 16),
          label: Text(
            _copied
                ? 'Copied'
                : _copyFailed
                ? 'Retry'
                : 'Copy',
          ),
          style: TextButton.styleFrom(
            foregroundColor: widget.theme.surfaceTextColor,
            visualDensity: VisualDensity.compact,
          ),
        ),
      );
    }
    return IconButton(
      tooltip: _copied
          ? 'Copied'
          : _copyFailed
          ? 'Copy failed'
          : 'Copy response',
      onPressed: _copy,
      icon: Icon(icon),
      iconSize: 18,
      style: IconButton.styleFrom(
        foregroundColor: widget.theme.backgroundTextColor.withValues(
          alpha: .75,
        ),
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
