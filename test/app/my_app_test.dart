import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/app/app.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/chat_models.dart';
import 'package:slm_ai_chatbot/features/llm/domain/local_llm_service.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_manager.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_search_result.dart';

void main() {
  testWidgets('composes, streams, and retries a chat answer', (tester) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final firstResponse = StreamController<String>();
    var attempts = 0;
    final llmService = _FakeLlmService(() {
      attempts++;
      return attempts == 1 ? firstResponse.stream : Stream.value('Recovered.');
    });

    await tester.pumpWidget(
      MyApp(modelManager: modelManager, askQuestion: _askQuestion(llmService)),
    );

    await tester.enterText(
      find.byType(TextField),
      'Why can my device not connect to the network?',
    );
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();

    expect(
      find.text('Why can my device not connect to the network?'),
      findsOneWidget,
    );
    expect(find.text('Thinking…'), findsOneWidget);

    firstResponse.add('Check ');
    await tester.pump();
    expect(find.text('Check '), findsOneWidget);

    firstResponse.addError(Exception('generation failed'));
    await tester.pump();
    expect(
      find.text('Unable to generate an answer with the local AI model.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Recovered.'), findsOneWidget);
    expect(attempts, 2);

    unawaited(firstResponse.close());
    await modelManager.dispose();
  });

  test('chat defaults are white-label and local-source aware', () {
    const configuration = AiChatConfiguration();
    const theme = AiChatTheme();

    expect(configuration.showLocalSources, isTrue);
    expect(configuration.scrollThreshold, 160);
    expect(theme.avatarLabel, 'AI');
  });
}

AskQuestionUseCase _askQuestion(_FakeLlmService llmService) {
  return AskQuestionUseCase(
    ragRepository: _FakeRagRepository(),
    llmService: llmService,
  );
}

class _ReadyModelRepository implements LocalModelRepository {
  @override
  Future<void> download({required void Function(int progress) onProgress}) {
    throw UnsupportedError('Already installed');
  }

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<void> load() async {}
}

class _FakeLlmService implements LocalLlmService {
  _FakeLlmService(this._responses);

  final Stream<String> Function() _responses;

  @override
  Future<void> dispose() async {}

  @override
  Stream<String> generate(String prompt) => _responses();

  @override
  Future<void> stop() async {}
}

class _FakeRagRepository implements RagRepository {
  @override
  Future<void> indexDocuments(Iterable<RagDocument> documents) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<List<RagSearchResult>> search({
    required String query,
    int topK = 1,
    double threshold = 0,
  }) async {
    return const [
      RagSearchResult(
        document: KnowledgeDocument(
          id: 'network',
          title: 'Device network connection guide',
          content: 'Connect the device to the network.',
          metadata: {},
        ),
        similarity: 1,
      ),
    ];
  }
}
