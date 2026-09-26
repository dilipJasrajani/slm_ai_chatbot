import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/chat/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_history.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/ai_chat_page.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/chat_controller.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/chat_models.dart';
import 'package:slm_ai_chatbot/features/llm/domain/local_llm_service.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_manager.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_search_result.dart';

void main() {
  testWidgets('visible assistant text is recorded after the chat frame', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final response = StreamController<String>();
    final askQuestion = AskQuestionUseCase(
      ragRepository: _RagRepository(),
      llmService: _LlmService(response.stream),
    );
    final controller = ChatController(
      modelManager: modelManager,
      askQuestion: askQuestion,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          modelManager: modelManager,
          askQuestion: askQuestion,
          controller: controller,
        ),
      ),
    );

    final sending = controller.send('Need help');
    final messageId = controller.state.messages.last.id;
    response.add('First text');
    await tester.pump();

    expect(find.text('First text'), findsOneWidget);
    expect(controller.isFirstRenderedTextPending(messageId), isFalse);

    await response.close();
    await sending;
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await modelManager.dispose();
  });

  testWidgets('first rendered text waits for a frame after streamed text', (
    tester,
  ) async {
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
    final sending = controller.send('Need help');
    final messageId = controller.state.messages.last.id;
    expect(controller.isFirstRenderedTextPending(messageId), isFalse);

    response.add('First text');
    await tester.pump();
    expect(controller.isFirstRenderedTextPending(messageId), isTrue);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.recordFirstRenderedText(messageId);
    });
    expect(controller.isFirstRenderedTextPending(messageId), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(controller.isFirstRenderedTextPending(messageId), isFalse);
    await response.close();
    await sending;
    controller.dispose();
    await modelManager.dispose();
  });

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
    expect(controller.state.messages.last.sources, isEmpty);
    expect(controller.state.messages.last.generationDuration, isNull);

    response.addError(Exception('failed'));
    await send;
    expect(controller.state.isTyping, isFalse);
    expect(controller.state.messages.last.isError, isTrue);
    expect(controller.state.messages.last.sources, isEmpty);
    expect(controller.state.messages.last.generationDuration, isNull);
    expect(
      controller.state.messages.last.text,
      'Unable to generate an answer with the local AI model.',
    );

    await response.close();
    controller.dispose();
    await modelManager.dispose();
  });

  test('attaches grounded documents only when the answer finishes', () async {
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
    response.add('Part ');
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.messages.last.sources, isEmpty);
    expect(controller.state.messages.last.generationDuration, isNull);
    expect(controller.state.messages.first.sources, isEmpty);

    await response.close();
    await send;
    expect(controller.state.messages.last.isStreaming, isFalse);
    expect(
      controller.state.messages.last.sources.single.title,
      'Need help guide',
    );
    expect(controller.state.messages.first.sources, isEmpty);
    expect(controller.state.messages.last.generationDuration, isNotNull);
    expect(controller.state.messages.first.generationDuration, isNull);

    controller.dispose();
    await modelManager.dispose();
  });

  test('keeps timing attached to each completed assistant message', () async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final secondResponse = StreamController<String>();
    final controller = ChatController(
      modelManager: modelManager,
      askQuestion: AskQuestionUseCase(
        ragRepository: _RagRepository(),
        llmService: _QueuedLlmService([
          Stream.value('First answer.'),
          secondResponse.stream,
        ]),
      ),
    );

    await controller.send('Need help');
    final first = controller.state.messages.last;
    expect(first.generationDuration, isNotNull);

    final secondSend = controller.send('Need help again');
    expect(controller.state.messages.last.generationDuration, isNull);
    secondResponse.add('Second answer.');
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.messages.last.generationDuration, isNull);
    await secondResponse.close();
    await secondSend;

    expect(controller.state.messages.last.generationDuration, isNotNull);
    expect(
      controller.state.messages[1].generationDuration,
      first.generationDuration,
    );
    expect(controller.state.messages[2].generationDuration, isNull);

    controller.dispose();
    await modelManager.dispose();
  });

  test('clears visual and domain conversation history', () async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final history = InMemoryConversationHistory();
    final controller = ChatController(
      modelManager: modelManager,
      askQuestion: AskQuestionUseCase(
        ragRepository: _RagRepository(),
        llmService: _LlmService(Stream.value('Hello!')),
        conversationHistory: history,
      ),
    );

    await controller.send('Hi');
    expect(controller.state.messages, hasLength(2));
    expect(history.messages, hasLength(2));

    controller.clearHistory();
    expect(controller.state.messages, isEmpty);
    expect(history.messages, isEmpty);

    controller.dispose();
    await modelManager.dispose();
  });

  test(
    'regenerates in place with fresh streaming, sources and timing',
    () async {
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      final history = InMemoryConversationHistory();
      final secondResponse = StreamController<String>();
      final controller = ChatController(
        modelManager: modelManager,
        askQuestion: AskQuestionUseCase(
          ragRepository: _RagRepository(),
          llmService: _QueuedLlmService([
            Stream.value('Original answer'),
            secondResponse.stream,
          ]),
          conversationHistory: history,
        ),
      );
      await controller.send('Need help');
      final original = controller.state.messages.last;
      expect(original.sources, hasLength(1));
      expect(history.messages, hasLength(2));

      final regenerate = controller.regenerate(original);
      expect(controller.state.messages, hasLength(2));
      expect(controller.state.messages.first.text, 'Need help');
      expect(controller.state.messages.last.id, original.id);
      expect(controller.state.messages.last.text, isEmpty);
      expect(controller.state.messages.last.isStreaming, isTrue);
      expect(controller.state.messages.last.sources, isEmpty);
      expect(controller.state.messages.last.generationDuration, isNull);
      expect(() => controller.regenerate(original), throwsStateError);

      secondResponse.add('New ');
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.messages.last.text, 'New ');
      expect(controller.state.messages.last.isStreaming, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      secondResponse.add('answer');
      await Future<void>.delayed(Duration.zero);
      await secondResponse.close();
      expect(await regenerate, isNull);
      expect(controller.state.messages, hasLength(2));
      expect(controller.state.messages.last.id, original.id);
      expect(controller.state.messages.last.text, 'New answer');
      expect(controller.state.messages.last.isStreaming, isFalse);
      expect(
        controller.state.messages.last.sources.single.title,
        'Need help guide',
      );
      expect(controller.state.messages.last.generationDuration, isNotNull);
      expect(
        controller.state.messages.last.generationDuration!,
        greaterThan(original.generationDuration!),
      );
      expect(history.messages.map((entry) => entry.text), [
        'Need help',
        'New answer',
      ]);
      controller.dispose();
      await modelManager.dispose();
    },
  );

  test(
    'restores prior response and history after regeneration failure',
    () async {
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      final history = InMemoryConversationHistory();
      final failedResponse = StreamController<String>();
      final controller = ChatController(
        modelManager: modelManager,
        askQuestion: AskQuestionUseCase(
          ragRepository: _RagRepository(),
          llmService: _QueuedLlmService([
            Stream.value('Original answer'),
            failedResponse.stream,
            Stream.value('Recovered answer'),
          ]),
          conversationHistory: history,
        ),
      );
      await controller.send('Need help');
      final original = controller.state.messages.last;
      final regeneration = controller.regenerate(original);
      failedResponse.add('Partial answer');
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.messages.last.text, 'Partial answer');
      failedResponse.addError(StateError('Model not ready'));
      final error = await regeneration;
      expect(error, 'Local AI model is not installed or could not be loaded.');
      expect(controller.state.messages.last, same(original));
      expect(controller.state.isTyping, isFalse);
      expect(history.messages.map((entry) => entry.text), [
        'Need help',
        'Original answer',
      ]);

      expect(await controller.regenerate(original), isNull);
      expect(controller.state.messages, hasLength(2));
      expect(controller.state.messages.last.text, 'Recovered answer');
      expect(history.messages.map((entry) => entry.text), [
        'Need help',
        'Recovered answer',
      ]);
      await failedResponse.close();
      controller.dispose();
      await modelManager.dispose();
    },
  );

  test(
    'retries failures in place without adding failed turns to history',
    () async {
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      final history = InMemoryConversationHistory();
      final failedRetry = StreamController<String>();
      final controller = ChatController(
        modelManager: modelManager,
        askQuestion: AskQuestionUseCase(
          ragRepository: _RagRepository(),
          llmService: _QueuedLlmService([
            Stream<String>.error(StateError('BackendInitException: internal')),
            failedRetry.stream,
            Stream.value('## Solution\n\nCheck `E123`.'),
          ]),
          conversationHistory: history,
        ),
      );

      await controller.send('Need help');
      final initialError = controller.state.messages.last;
      final user = controller.state.messages.first;
      expect(initialError.isError, isTrue);
      expect(
        initialError.text,
        'Local AI model is not installed or could not be loaded.',
      );
      expect(history.messages, isEmpty);
      expect(controller.state.messages, hasLength(2));

      final retry = controller.retry(initialError);
      expect(controller.state.isTyping, isTrue);
      expect(controller.state.canSend, isFalse);
      expect(controller.state.messages, hasLength(2));
      expect(controller.state.messages.first, same(user));
      expect(controller.state.messages.last.id, initialError.id);
      expect(controller.state.messages.last.isStreaming, isTrue);
      expect(controller.state.messages.last.isError, isFalse);
      expect(controller.state.messages.last.text, isEmpty);
      expect(() => controller.retry(initialError), throwsStateError);
      await controller.send('Second question');
      expect(controller.state.messages, hasLength(2));
      failedRetry.add('Partial answer');
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.messages.last.text, 'Partial answer');
      failedRetry.addError(Exception('Stack trace: internal'));
      await retry;
      expect(controller.state.isTyping, isFalse);
      expect(controller.state.messages, hasLength(2));
      expect(controller.state.messages.last.id, initialError.id);
      expect(controller.state.messages.last.isError, isTrue);
      expect(
        controller.state.messages.last.text,
        'Unable to generate an answer with the local AI model.',
      );
      expect(controller.state.messages.last.sources, isEmpty);
      expect(controller.state.messages.last.generationDuration, isNull);
      expect(history.messages, isEmpty);

      await controller.retry(controller.state.messages.last);
      expect(controller.state.messages, hasLength(2));
      expect(controller.state.messages.last.id, initialError.id);
      expect(controller.state.messages.last.isError, isFalse);
      expect(
        controller.state.messages.last.text,
        '## Solution\n\nCheck `E123`.',
      );
      expect(controller.state.messages.last.sources, hasLength(1));
      expect(controller.state.messages.last.generationDuration, isNotNull);
      expect(history.messages.map((entry) => entry.text), [
        'Need help',
        '## Solution\n\nCheck `E123`.',
      ]);
      expect(
        () => controller.retry(controller.state.messages.last),
        throwsStateError,
      );
      await failedRetry.close();
      controller.dispose();
      await modelManager.dispose();
    },
  );

  test('retry rejects errors without a matching original question', () async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final controller = ChatController(
      modelManager: modelManager,
      askQuestion: AskQuestionUseCase(
        ragRepository: _RagRepository(),
        llmService: _LlmService(Stream.value('Answer')),
      ),
    );
    expect(
      () => controller.retry(
        const ChatMessage(
          id: 'missing',
          author: ChatAuthor.assistant,
          text: 'Failed',
          isError: true,
        ),
      ),
      throwsStateError,
    );
    await controller.send('Need help');
    expect(
      () => controller.retry(controller.state.messages.last),
      throwsStateError,
    );
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

class _QueuedLlmService implements LocalLlmService {
  _QueuedLlmService(this.responses);

  final List<Stream<String>> responses;
  var _nextResponse = 0;

  @override
  Stream<String> generate(String prompt) => responses[_nextResponse++];

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
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
