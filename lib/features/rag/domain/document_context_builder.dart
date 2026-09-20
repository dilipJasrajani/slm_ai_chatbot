import 'knowledge_document.dart';

/// Formats grounded documents as the context supplied to the RAG prompt.
class DocumentContextBuilder {
  const DocumentContextBuilder();

  String build(Iterable<KnowledgeDocument> documents) {
    return documents
        .toList(growable: false)
        .indexed
        .map(
          (entry) => [
            'Knowledge Document ${entry.$1 + 1}',
            '',
            'Title:',
            entry.$2.title,
            '',
            'Content:',
            entry.$2.content,
            if (entry.$2.metadata.isNotEmpty) ...[
              '',
              'Metadata:',
              ..._metadataLines(entry.$2.metadata),
            ],
          ].join('\n'),
        )
        .join('\n\n');
  }

  Iterable<String> _metadataLines(Map<String, dynamic> metadata) {
    final keys = metadata.keys.toList()..sort();
    return keys.map((key) => '$key: ${metadata[key]}');
  }
}
