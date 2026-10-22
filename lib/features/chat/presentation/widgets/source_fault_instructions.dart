import 'package:flutter/material.dart';
import 'package:slm_ai_chatbot/features/rag/domain/document_context_builder.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';

import '../ai_chat_configuration.dart';

/// Plain text preserves source wording independently of model output/Markdown.
class SourceFaultInstructions extends StatefulWidget {
  const SourceFaultInstructions({
    required this.documents,
    required this.theme,
    super.key,
  });

  final List<KnowledgeDocument> documents;
  final AiChatTheme theme;

  @override
  State<SourceFaultInstructions> createState() =>
      _SourceFaultInstructionsState();
}

class _SourceFaultInstructionsState extends State<SourceFaultInstructions> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: widget.theme.assistantTextColor,
      height: 1.4,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          expanded: _expanded,
          child: TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              foregroundColor: widget.theme.assistantTextColor,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: style?.copyWith(fontWeight: FontWeight.w500),
            ),
            icon: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(_expanded ? 'Hide sources' : 'View sources'),
          ),
        ),
        if (_expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4, bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: widget.theme.borderColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              const DocumentContextBuilder().build(widget.documents),
              style: style,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'ViSage explanation',
          style: style?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
