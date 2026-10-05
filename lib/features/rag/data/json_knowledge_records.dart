import 'dart:convert';

import '../domain/knowledge_document.dart';

/// Converts JSON records of unknown shape into independently searchable documents.
class JsonKnowledgeRecords {
  const JsonKnowledgeRecords({required this.assetPath});

  final String assetPath;

  List<KnowledgeDocument> parse(Object? root) {
    final records = switch (root) {
      List<Object?> values => values.indexed.map(
        (item) => (path: '${item.$1}', value: item.$2),
      ),
      Map<String, dynamic> values => _rootRecords(values),
      _ => throw const FormatException(
        'Knowledge-base root must be a JSON object or list of records.',
      ),
    };
    return List.unmodifiable([
      for (final record in records) _record(record.value, record.path),
    ]);
  }

  Iterable<({String path, Object? value})> _rootRecords(
    Map<String, dynamic> root,
  ) sync* {
    if (root['entries'] case final List<dynamic> entries) {
      for (final (index, value) in entries.indexed) {
        yield (path: 'entries/$index', value: value);
      }
      return;
    }
    if (root['documents'] case final List<dynamic> documents) {
      for (final (index, value) in documents.indexed) {
        yield (path: 'documents/$index', value: value);
      }
      return;
    }
    final collections = root.entries.where((entry) => entry.value is List);
    if (collections.isNotEmpty) {
      for (final collection in collections) {
        for (final (index, value) in (collection.value as List).indexed) {
          yield (path: '${collection.key}/$index', value: value);
        }
      }
      return;
    }
    yield (path: 'root', value: root);
  }

  KnowledgeDocument _record(Object? value, String path) {
    if (value is! Map<String, dynamic> || value.isEmpty) {
      throw FormatException(
        'Knowledge-base record "$path" in "$assetPath" must be a non-empty JSON object.',
      );
    }
    final id = _nonEmpty(value['id']) ?? '$assetPath#$path';
    final title =
        _nonEmpty(value['title']) ??
        _nonEmpty(value['name']) ??
        _nonEmpty(value['code']) ??
        id;
    final content =
        _nonEmpty(value['text']) ??
        _nonEmpty(value['content']) ??
        _describe(value);
    if (content.isEmpty) {
      throw FormatException(
        'Knowledge-base record "$path" in "$assetPath" has no searchable content.',
      );
    }
    final metadata = <String, dynamic>{
      for (final key in [
        'type',
        'entity_type',
        'message_type',
        'pages',
        'source_passage_ids',
        'source_chunk_id',
        'kb_entity_id',
      ])
        if (value.containsKey(key)) key: value[key],
      if (value['metadata'] case final Map<String, dynamic> fields) ...fields,
    };
    final code = _nonEmpty(value['code']) ?? _messageCode(value);
    if (code != null) metadata['code'] = code;
    final searchTerms = switch (value['phrasings']) {
      final List<dynamic> phrases =>
        phrases
            .whereType<String>()
            .where((phrase) => phrase.trim().isNotEmpty)
            .join('\n'),
      _ => _nonEmpty(value['search_text']),
    };
    return KnowledgeDocument(
      id: id,
      title: title,
      content: content,
      measures: _nonEmpty(value['measures']),
      searchText: searchTerms?.isNotEmpty == true ? searchTerms : null,
      metadata: Map.unmodifiable(metadata),
    );
  }

  String? _messageCode(Map<String, dynamic> value) {
    if (value['entity_type'] != 'message') return null;
    final text = value['text'];
    if (text is! String) return null;
    return RegExp(r'^Code: ([A-Za-z]+\.\d+)\b').firstMatch(text)?.group(1);
  }

  String _describe(Map<String, dynamic> record) {
    return record.entries
        .where(
          (entry) => !{
            'id',
            'title',
            'name',
            'search_text',
            'phrasings',
            'metadata',
          }.contains(entry.key),
        )
        .map((entry) => '${entry.key}: ${_format(entry.value)}')
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  }

  String _format(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  String? _nonEmpty(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value;
  }
}
