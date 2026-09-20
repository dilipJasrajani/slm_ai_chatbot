import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';

import '../domain/retrieval_evaluation_case.dart';
import '../domain/retrieval_evaluation_dataset.dart';
import '../domain/retrieval_evaluation_dataset_source.dart';

class JsonRetrievalEvaluationDatasetSource
    implements RetrievalEvaluationDatasetSource {
  JsonRetrievalEvaluationDatasetSource({
    required AssetBundle assetBundle,
    this.assetPath = 'assets/evaluation/retrieval_cases.json',
  }) : _assetBundle = assetBundle;

  final AssetBundle _assetBundle;
  final String assetPath;

  @override
  Future<RetrievalEvaluationDataset> loadDataset() async {
    final source = await _loadSource();
    return _parseDataset(_decodeSource(source));
  }

  Future<String> _loadSource() async {
    try {
      return await _assetBundle.loadString(assetPath);
    } on FlutterError catch (error) {
      throw StateError(
        'Unable to load retrieval-evaluation asset "$assetPath": $error',
      );
    }
  }

  Object? _decodeSource(String source) {
    try {
      return jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException(
        'Retrieval-evaluation asset "$assetPath" contains invalid JSON: '
        '${error.message}',
        error.source,
        error.offset,
      );
    }
  }

  RetrievalEvaluationDataset _parseDataset(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Retrieval-evaluation root must be a JSON object.',
      );
    }
    if (decoded['version'] is! int) {
      throw const FormatException(
        'Retrieval-evaluation root must contain an integer "version".',
      );
    }
    final cases = decoded['cases'];
    if (cases is! List) {
      throw const FormatException(
        'Retrieval-evaluation root must contain a "cases" list.',
      );
    }

    return RetrievalEvaluationDataset(
      cases: List.unmodifiable([
        for (var index = 0; index < cases.length; index++)
          _parseCase(cases[index], index),
      ]),
    );
  }

  RetrievalEvaluationCase _parseCase(Object? record, int index) {
    if (record is! Map<String, dynamic>) {
      throw FormatException(
        'Retrieval-evaluation case at index $index must be a JSON object.',
      );
    }
    final topK = record['topK'];
    if (topK != null && (topK is! int || topK < 1)) {
      throw FormatException(
        'Retrieval-evaluation case at index $index must contain a positive '
        '"topK" integer when specified.',
      );
    }

    return RetrievalEvaluationCase(
      id: _requiredString(record, 'id', index),
      query: _requiredString(record, 'query', index),
      expectedDocumentIds: _expectedDocumentIds(record, index),
      topK: topK as int?,
    );
  }

  String _requiredString(Map<String, dynamic> record, String field, int index) {
    final value = record[field];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        'Retrieval-evaluation case at index $index must contain a non-empty '
        '"$field" string.',
      );
    }
    return value;
  }

  List<String> _expectedDocumentIds(Map<String, dynamic> record, int index) {
    final ids = record['expectedDocumentIds'];
    if (ids is! List || ids.any((id) => id is! String || id.trim().isEmpty)) {
      throw FormatException(
        'Retrieval-evaluation case at index $index must contain an '
        '"expectedDocumentIds" list of non-empty strings.',
      );
    }
    return List.unmodifiable(ids.cast<String>());
  }
}
