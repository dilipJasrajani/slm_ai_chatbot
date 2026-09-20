import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';

import '../../domain/chat/chat_intent_evaluation_case.dart';
import '../../domain/chat/chat_intent_evaluation_dataset.dart';
import '../../domain/chat/chat_intent_evaluation_dataset_source.dart';
import '../../domain/chat/chat_route.dart';

class JsonChatIntentEvaluationDatasetSource
    implements ChatIntentEvaluationDatasetSource {
  JsonChatIntentEvaluationDatasetSource({
    required AssetBundle assetBundle,
    this.assetPath = 'assets/evaluation/chat_intent_cases.json',
  }) : _assetBundle = assetBundle;

  final AssetBundle _assetBundle;
  final String assetPath;

  @override
  Future<ChatIntentEvaluationDataset> loadDataset() async {
    final source = await _loadSource();
    return _parseDataset(_decodeSource(source));
  }

  Future<String> _loadSource() async {
    try {
      return await _assetBundle.loadString(assetPath);
    } on FlutterError catch (error) {
      throw StateError(
        'Unable to load chat-intent evaluation asset "$assetPath": $error',
      );
    }
  }

  Object? _decodeSource(String source) {
    try {
      return jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException(
        'Chat-intent evaluation asset "$assetPath" contains invalid JSON: '
        '${error.message}',
        error.source,
        error.offset,
      );
    }
  }

  ChatIntentEvaluationDataset _parseDataset(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Chat-intent evaluation root must be a JSON object.',
      );
    }
    if (decoded['version'] is! int) {
      throw const FormatException(
        'Chat-intent evaluation root must contain an integer "version".',
      );
    }
    final cases = decoded['cases'];
    if (cases is! List) {
      throw const FormatException(
        'Chat-intent evaluation root must contain a "cases" list.',
      );
    }

    return ChatIntentEvaluationDataset(
      cases: List.unmodifiable([
        for (var index = 0; index < cases.length; index++)
          _parseCase(cases[index], index),
      ]),
    );
  }

  ChatIntentEvaluationCase _parseCase(Object? record, int index) {
    if (record is! Map<String, dynamic>) {
      throw FormatException(
        'Chat-intent evaluation case at index $index must be a JSON object.',
      );
    }

    return ChatIntentEvaluationCase(
      id: _requiredString(record, 'id', index),
      message: _requiredString(record, 'message', index),
      expectedRoute: _expectedRoute(record, index),
    );
  }

  String _requiredString(Map<String, dynamic> record, String field, int index) {
    final value = record[field];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        'Chat-intent evaluation case at index $index must contain a non-empty '
        '"$field" string.',
      );
    }
    return value;
  }

  ChatRoute _expectedRoute(Map<String, dynamic> record, int index) {
    final value = record['expectedRoute'];
    if (value is! String) {
      throw FormatException(
        'Chat-intent evaluation case at index $index must contain an '
        '"expectedRoute" string.',
      );
    }

    final route = tryParseChatRouteLabel(value);
    if (route == null) {
      throw FormatException(
        'Chat-intent evaluation case at index $index must use expectedRoute '
        'CHAT or KNOWLEDGE.',
      );
    }
    return route;
  }
}
