import 'dart:convert';

import 'knowledge_document.dart';

/// Formats grounded documents as the context supplied to the RAG prompt.
class DocumentContextBuilder {
  const DocumentContextBuilder();

  static const _representedFields = {
    'id',
    'title',
    'name',
    'text',
    'content',
    'type',
    'entity_type',
    'message_type',
    'pages',
    'search_text',
    'phrasings',
    'searchable',
    'metadata',
    'source_passage_ids',
    'source_chunk_id',
    'kb_entity_id',
    'related_entities',
    'related_messages',
    'fix_procedures',
    'resolves',
    'measures',
    'steps',
  };

  String build(Iterable<KnowledgeDocument> documents) {
    return documents
        .toList(growable: false)
        .indexed
        .map((entry) => _format(entry.$1 + 1, entry.$2))
        .join('\n\n');
  }

  String _format(int index, KnowledgeDocument document) {
    final Object? decoded;
    try {
      decoded = jsonDecode(document.content);
    } on FormatException {
      return [
        'Knowledge Document $index',
        '',
        'Title:',
        '${document.id} ${document.title}',
        '',
        'Content:',
        document.content,
        if (document.measures != null) ...['', 'Measures:', document.measures!],
        if (document.metadata.isNotEmpty) ...[
          '',
          'Metadata:',
          ..._metadataLines(document.metadata),
        ],
      ].join('\n');
    }
    if (decoded is! Map<String, dynamic>) {
      return 'Knowledge Document $index\n\nTitle:\n${document.id} ${document.title}'
          '\n\nContent:\n${document.content}';
    }

    final text = decoded['text'];
    final content = decoded['content'];
    final factualContent = text is String && text.trim().isNotEmpty
        ? text
        : content is String && content.trim().isNotEmpty
        ? content
        : jsonEncode({
            for (final entry in decoded.entries)
              if (!{
                'id',
                'title',
                'name',
                'search_text',
                'phrasings',
                'searchable',
              }.contains(entry.key))
                entry.key: entry.value,
          });
    final additionalFacts =
        text is String && text.trim().isNotEmpty ||
            content is String && content.trim().isNotEmpty
        ? {
            for (final entry in decoded.entries)
              if (!_representedFields.contains(entry.key))
                entry.key: entry.value,
          }
        : const <String, dynamic>{};
    final pages = decoded['pages'] ?? document.metadata['pages'];
    return [
      'Knowledge Document $index',
      '',
      'Title:',
      '${document.id} ${document.title}',
      '',
      'Content:',
      factualContent,
      if (additionalFacts.isNotEmpty)
        'Additional facts: ${jsonEncode(additionalFacts)}',
      if (pages is List && pages.isNotEmpty)
        'Source pages: ${pages.join(', ')}',
      if (document.metadata['code'] case final String code)
        if (!factualContent.contains(code)) 'Code: $code',
    ].join('\n');
  }

  Iterable<String> _metadataLines(Map<String, dynamic> metadata) {
    final keys = metadata.keys.toList()..sort();
    return keys.map((key) => '$key: ${metadata[key]}');
  }
}
