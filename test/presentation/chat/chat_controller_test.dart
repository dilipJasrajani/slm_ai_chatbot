import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/domain/llm/local_llm_service.dart';
import 'package:slm_ai_chatbot/domain/model/local_model_manager.dart';
import 'package:slm_ai_chatbot/domain/model/local_model_repository.dart';
import 'package:slm_ai_chatbot/domain/rag/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/domain/rag/knowledge_document.dart';
import 'package:slm_ai_chatbot/domain/rag/rag_document.dart';
import 'package:slm_ai_chatbot/domain/rag/rag_repository.dart';
import 'package:slm_ai_chatbot/domain/rag/rag_search_result.dart';
import 'package:slm_ai_chatbot/presentation/chat/chat_controller.dart';

void main() {
  test('progresses through streamed chunks and a controlled error', () async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final response = StreamController<String>();
    final controller = ChatController(
      modelManager: modelManager,
      askQuestion: AskQuestionUseCase(
        ragRepository: _RagRepository(),
        llmService: _LlmService(response.stream),
      ),
    );

    final send = controller.send('Need help');
    expect(controller.state.messages, hasLength(2));
    expect(controller.state.isTyping, isTrue);
    expect(controller.state.messages.last.isStreaming, isTrue);

    response.add('Part ');
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.messages.last.text, 'Part ');
    expect(controller.state.messages.last.isStreaming, isTrue);

    response.addError(Exception('failed'));
    await send;
    expect(controller.state.isTyping, isFalse);
    expect(controller.state.messages.last.isError, isTrue);
    expect(
      controller.state.messages.last.text,
      'Unable to generate an answer with the local AI model.',
    );

    await response.close();
    controller.dispose();
    await modelManager.dispose();
  });
}

class _ReadyModelRepository implements LocalModelRepository {
  @override
  Future<void> download({
    required void Function(int progress) onProgress,
  }) async {}

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<void> load() async {}
}

class _LlmService implements LocalLlmService {
  _LlmService(this.response);

  final Stream<String> response;

  @override
  Future<void> dispose() async {}

  @override
  Stream<String> generate(String prompt) => response;

  @override
  Future<void> stop() async {}
}

class _RagRepository implements RagRepository {
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
          id: 'guide',
          title: 'Need help guide',
          content: 'Help is available in this guide.',
          metadata: {},
        ),
        similarity: 1,
      ),
    ];
  }
}
