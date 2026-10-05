import 'knowledge_document.dart';

/// Produces the stable text embedded and indexed for one knowledge document.
class DocumentSearchableText {
  const DocumentSearchableText();

  String format(KnowledgeDocument document) {
    final metadataKeys = document.metadata.keys.toList()..sort();
    final lines = [
      'Id: ${document.id}',
      'Title: ${document.title}',
      if (document.searchText != null) ...[
        '',
        'Search terms:',
        document.searchText!,
      ],
      '',
      'Content:',
      document.content,
    ];
    if (document.measures != null) {
      lines.addAll(['', 'Measures:', document.measures!]);
    }
    if (document.metadata.isNotEmpty) {
      lines.addAll([
        '',
        'Metadata:',
        ...metadataKeys.map(
          (key) => '$key: ${_formatValue(document.metadata[key])}',
        ),
      ]);
    }
    return lines.join('\n');
  }

  String _formatValue(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '$key: ${_formatValue(value[key])}').join(', ')}}';
    }
    if (value is Iterable) {
      return '[${value.map(_formatValue).join(', ')}]';
    }
    return value.toString();
  }
}
