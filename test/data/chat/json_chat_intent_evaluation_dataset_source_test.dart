import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/data/chat/json_chat_intent_evaluation_dataset_source.dart';
import 'package:slm_ai_chatbot/domain/chat/chat_route.dart';

void main() {
  test('parses valid chat-intent evaluation cases', () async {
    final source = JsonChatIntentEvaluationDatasetSource(
      assetBundle: _StringAssetBundle(
        jsonEncode({
          'version': 1,
          'cases': [
            {'id': 'greeting', 'message': 'Hi there', 'expectedRoute': 'CHAT'},
            {
              'id': 'knowledge',
              'message': 'What does E123 mean?',
              'expectedRoute': 'KNOWLEDGE',
            },
          ],
        }),
      ),
    );

    final dataset = await source.loadDataset();

    expect(dataset.cases, hasLength(2));
    expect(dataset.cases.first.expectedRoute, ChatRoute.chat);
    expect(dataset.cases.last.expectedRoute, ChatRoute.knowledge);
  });

  test('rejects invalid expected routes', () {
    final source = JsonChatIntentEvaluationDatasetSource(
      assetBundle: _StringAssetBundle(
        jsonEncode({
          'version': 1,
          'cases': [
            {'id': 'invalid', 'message': 'Hi there', 'expectedRoute': 'MAYBE'},
          ],
        }),
      ),
    );

    expect(source.loadDataset, throwsFormatException);
  });

  testWidgets('loads the bundled chat-intent evaluation asset', (tester) async {
    final source = JsonChatIntentEvaluationDatasetSource(
      assetBundle: rootBundle,
    );

    final dataset = await source.loadDataset();

    expect(dataset.cases, hasLength(10));
    expect(dataset.cases.first.id, 'chat-greeting');
    expect(dataset.cases.last.expectedRoute, ChatRoute.knowledge);
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
