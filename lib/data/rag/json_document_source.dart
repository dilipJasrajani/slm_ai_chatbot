import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';

import '../../domain/rag/document_source.dart';
import '../../domain/rag/knowledge_document.dart';

class JsonDocumentSource implements DocumentSource {
  JsonDocumentSource({
    required AssetBundle assetBundle,
    this.assetPath = 'assets/knowledge_base/documents.json',
  }) : _assetBundle = assetBundle;

  final AssetBundle _assetBundle;
  final String assetPath;

  @override
  Future<List<KnowledgeDocument>> loadDocuments() async {
    final source = await _loadSource();
    final decoded = _decodeSource(source);
    return _parseDocuments(decoded);
  }

  Future<String> _loadSource() async {
    try {
      return await _assetBundle.loadString(assetPath);
    } on FlutterError catch (error) {
      throw StateError(
        'Unable to load knowledge-base asset "$assetPath": $error',
      );
    }
  }

  Object? _decodeSource(String source) {
    try {
      return jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException(
        'Knowledge-base asset "$assetPath" contains invalid JSON: '
        '${error.message}',
        error.source,
        error.offset,
      );
    }
  }

  List<KnowledgeDocument> _parseDocuments(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Knowledge-base root must be a JSON object.');
    }
    if (decoded['version'] is! int) {
      throw const FormatException(
        'Knowledge-base root must contain an integer "version".',
      );
    }

    final records = decoded['documents'];
    if (records is! List) {
      throw const FormatException(
        'Knowledge-base root must contain a "documents" list.',
      );
    }

    return List.unmodifiable([
      for (var index = 0; index < records.length; index++)
        _parseDocument(records[index], index),
    ]);
  }

  KnowledgeDocument _parseDocument(Object? record, int index) {
    if (record is! Map<String, dynamic>) {
      throw FormatException('Document at index $index must be a JSON object.');
    }

    return KnowledgeDocument(
      id: _requiredString(record, 'id', index),
      title: _requiredString(record, 'title', index),
      content: _requiredString(record, 'content', index),
      metadata: _requiredMetadata(record, index),
    );
  }

  String _requiredString(Map<String, dynamic> record, String field, int index) {
    final value = record[field];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        'Document at index $index must contain a non-empty "$field" string.',
      );
    }
    return value;
  }

  Map<String, dynamic> _requiredMetadata(
    Map<String, dynamic> record,
    int index,
  ) {
    final metadata = record['metadata'];
    if (metadata is! Map<String, dynamic>) {
      throw FormatException(
        'Document at index $index must contain a "metadata" JSON object.',
      );
    }
    return Map.unmodifiable(metadata);
  }
}
