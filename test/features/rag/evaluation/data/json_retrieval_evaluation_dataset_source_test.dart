import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/evaluation/data/json_retrieval_evaluation_dataset_source.dart';

void main() {
  test(
    'parses valid cases including expected IDs and an unrelated case',
    () async {
      final source = JsonRetrievalEvaluationDatasetSource(
        assetBundle: _StringAssetBundle(
          jsonEncode({
            'version': 1,
            'cases': [
              {
                'id': 'network',
                'query': 'My device cannot connect to Wi-Fi.',
                'expectedDocumentIds': ['error-e123'],
              },
              {
                'id': 'unrelated',
                'query': 'What is the capital of France?',
                'expectedDocumentIds': [],
              },
            ],
          }),
        ),
      );

      final dataset = await source.loadDataset();

      expect(dataset.cases, hasLength(2));
      expect(dataset.cases.first.expectedDocumentIds, ['error-e123']);
      expect(dataset.cases.last.expectedDocumentIds, isEmpty);
    },
  );

  test('parses an optional positive topK override', () async {
    final source = JsonRetrievalEvaluationDatasetSource(
      assetBundle: _StringAssetBundle(
        jsonEncode({
          'version': 1,
          'cases': [
            {
              'id': 'network',
              'query': 'E123',
              'expectedDocumentIds': ['error-e123'],
              'topK': 2,
            },
          ],
        }),
      ),
    );

    final dataset = await source.loadDataset();

    expect(dataset.cases.single.topK, 2);
  });

  test('rejects malformed JSON', () {
    final source = JsonRetrievalEvaluationDatasetSource(
      assetBundle: _StringAssetBundle('{'),
    );

    expect(source.loadDataset, throwsFormatException);
  });

  test('rejects invalid expected document IDs', () {
    final source = JsonRetrievalEvaluationDatasetSource(
      assetBundle: _StringAssetBundle(
        jsonEncode({
          'version': 1,
          'cases': [
            {
              'id': 'invalid',
              'query': 'E123',
              'expectedDocumentIds': [42],
            },
          ],
        }),
      ),
    );

    expect(source.loadDataset, throwsFormatException);
  });

  testWidgets('loads the bundled retrieval evaluation asset', (tester) async {
    final source = JsonRetrievalEvaluationDatasetSource(
      assetBundle: rootBundle,
    );

    final dataset = await source.loadDataset();

    expect(dataset.cases, hasLength(13));
    expect(dataset.cases.first.id, 'network-exact-identifier');
    expect(dataset.cases.last.expectedDocumentIds, isEmpty);
  });
}

class _StringAssetBundle extends CachingAssetBundle {
  _StringAssetBundle(this._content);

  final String _content;

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(_content));
    return ByteData.sublistView(bytes);
  }
}
