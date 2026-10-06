import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/chat/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_history.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/ai_chat_page.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/cubit/chat_cubit.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/cubit/chat_state.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/models/chat_message.dart';
import 'package:slm_ai_chatbot/features/llm/domain/local_llm_service.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_manager.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_repository.dart';
import 'package:slm_ai_chatbot/features/model/domain/model_status.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_search_result.dart';

void main() {
  test(
    'emits every state in order while state changes synchronously',
    () async {
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      final response = StreamController<String>();
      final cubit = ChatCubit(
        modelManager: modelManager,
        askQuestion: AskQuestionUseCase(
          ragRepository: _RagRepository(),
          llmService: _LlmService(response.stream),
        ),
      );
      final states = <ChatState>[];
      final subscription = cubit.stream.listen(states.add);

      final sending = cubit.send('  Need help  ');
      expect(cubit.state.messages.first.text, 'Need help');
      expect(cubit.state.isTyping, isTrue);
      expect(cubit.state.canSend, isFalse);
      expect(states, isEmpty);
      await cubit.send('Blocked second send');
      cubit.clearHistory();
      expect(cubit.state.messages, hasLength(2));

      response.add('Part');
      await Future<void>.delayed(Duration.zero);
      response.add('');
      await Future<void>.delayed(Duration.zero);
      response.add(' two');
      await Future<void>.delayed(Duration.zero);
      await response.close();
      await sending;
      await Future<void>.delayed(Duration.zero);

      expect(states.map((state) => state.messages.last.text), [
        '',
        'Part',
        'Part',
        'Part two',
        'Part two',
        'Part two',
      ]);
      expect(states.map((state) => state.isTyping), [
        true,
        true,
        true,
        true,
        true,
        false,
      ]);
      expect(states.map((state) => state.messages.last.isStreaming), [
        true,
        true,
        true,
        true,
        false,
        false,
      ]);
      expect(identical(states[1], states[2]), isFalse);
      expect(
        states.take(4).every((state) => state.messages.last.sources.isEmpty),
        isTrue,
      );
      expect(states[4].messages.last.sources, hasLength(1));
      expect(states[4].messages.last.generationDuration, isNotNull);
      expect(states.last.canSend, isTrue);

      cubit.clearHistory();
      expect(cubit.state.messages, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(states.last.messages, isEmpty);
      await subscription.cancel();
      await cubit.close();
      await modelManager.dispose();
    },
  );

  test(
    'close cancels once and ignores late generation and new actions',
    () async {
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      final response = StreamController<String>();
      final llm = _LlmService(response.stream);
      final cubit = ChatCubit(
        modelManager: modelManager,
        askQuestion: AskQuestionUseCase(
          ragRepository: _RagRepository(),
          llmService: llm,
        ),
      );
      final states = <ChatState>[];
      var streamDone = false;
      final subscription = cubit.stream.listen(
        states.add,
        onDone: () => streamDone = true,
      );
      final sending = cubit.send('Need help');
      response.add('First text');
      await Future<void>.delayed(Duration.zero);
      final lastState = cubit.state;
      final assistantId = lastState.messages.last.id;
      expect(cubit.isFirstRenderedTextPending(assistantId), isTrue);

      final closing = cubit.close();
      expect(cubit.isClosed, isTrue);
      expect(cubit.close(), same(closing));
      expect(llm.stopCalls, 1);
      expect(cubit.isFirstRenderedTextPending(assistantId), isFalse);
      await cubit.send('Late question');
      cubit.clearHistory();
      expect(() => cubit.retry(lastState.messages.last), throwsStateError);
      expect(() => cubit.regenerate(lastState.messages.last), throwsStateError);
      expect(() => cubit.retryModelInitialization(), throwsStateError);
      response.add('Late text');
      await sending;
      await response.close();
      await closing;
      await modelManager.ensureReady();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, same(lastState));
      expect(states.last, same(lastState));
      expect(streamDone, isTrue);
      expect(llm.generateCalls, 1);
      await subscription.cancel();
      await modelManager.dispose();
    },
  );

  test('late retrieval results cannot emit after close', () async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final repository = _DelayedRagRepository();
    final llm = _LlmService(Stream.value('Late answer'));
    final cubit = ChatCubit(
      modelManager: modelManager,
      askQuestion: AskQuestionUseCase(
        ragRepository: repository,
        llmService: llm,
      ),
    );
    final sending = cubit.send('Need help');
    await Future<void>.delayed(Duration.zero);
    final state = cubit.state;
    expect(state.isTyping, isTrue);
    await cubit.close();
    expect(llm.stopCalls, 1);
    repository.result.complete(const []);
    await sending;
    expect(cubit.state, same(state));
    expect(cubit.state.messages.last.text, isEmpty);
    await modelManager.dispose();
  });

  test('late knowledge success or failure cannot emit after close', () async {
    for (final fail in [false, true]) {
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      final knowledge = Completer<void>();
      final cubit = ChatCubit(
        modelManager: modelManager,
        askQuestion: AskQuestionUseCase(
          ragRepository: _RagRepository(),
          llmService: _LlmService(Stream.value('unused')),
        ),
        prepareKnowledgeBase: () => knowledge.future,
      );
      final state = cubit.state;
      expect(state.isPreparingKnowledge, isTrue);
      final closing = cubit.close();
      if (fail) {
        knowledge.completeError(StateError('Late preparation failure'));
      } else {
        knowledge.complete();
      }
      await closing;
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, same(state));
      await modelManager.dispose();
    }
  });

  test('late model readiness cannot start knowledge after close', () async {
    final repository = _StagedModelRepository();
    final modelManager = LocalModelManager(repository);
    var preparationCalls = 0;
    final cubit = ChatCubit(
      modelManager: modelManager,
      askQuestion: AskQuestionUseCase(
        ragRepository: _RagRepository(),
        llmService: _LlmService(Stream.value('unused')),
      ),
      prepareKnowledgeBase: () async {
        preparationCalls++;
      },
    );
    await Future<void>.delayed(Duration.zero);
    final state = cubit.state;
    await cubit.close();
    repository.finishDownload.complete();
    repository.finishLoading.complete();
    await modelManager.ensureReady();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state, same(state));
    expect(preparationCalls, 0);
    await modelManager.dispose();
  });

  testWidgets('page adopts but never closes an injected cubit', (tester) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final llm = _LlmService(Stream.value('Answer'));
    final askQuestion = AskQuestionUseCase(
      ragRepository: _RagRepository(),
      llmService: llm,
    );
    final cubit = ChatCubit(
      modelManager: modelManager,
      askQuestion: askQuestion,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          modelManager: modelManager,
          askQuestion: askQuestion,
          cubit: cubit,
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    expect(cubit.isClosed, isFalse);
    expect(llm.stopCalls, 0);
    final sending = cubit.send('Need help');
    await tester.pump();
    await sending;
    expect(cubit.state.messages.last.text, 'Answer');
    await tester.runAsync(cubit.close);
    expect(llm.stopCalls, 1);
    await modelManager.dispose();
  });

  testWidgets('page closes its own cubit and ignores late knowledge', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final knowledge = Completer<void>();
    final llm = _LlmService(Stream.value('unused'));
    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          modelManager: modelManager,
          askQuestion: AskQuestionUseCase(
            ragRepository: _RagRepository(),
            llmService: llm,
          ),
          prepareKnowledgeBase: () => knowledge.future,
        ),
      ),
    );
    final cubit = tester
        .widget<BlocConsumer<ChatCubit, ChatState>>(
          find.byType(BlocConsumer<ChatCubit, ChatState>),
        )
        .bloc!;
    await tester.pumpWidget(const SizedBox());
    expect(cubit.isClosed, isTrue);
    expect(llm.stopCalls, 1);
    final state = cubit.state;
    knowledge.complete();
    await tester.pump();
    expect(cubit.state, same(state));
    expect(tester.takeException(), isNull);
    await tester.runAsync(cubit.close);
    await modelManager.dispose();
  });

  test('prepares knowledge only after the model finishes loading', () async {
    final repository = _StagedModelRepository();
    final modelManager = LocalModelManager(repository);
    final knowledgePrepared = Completer<void>();
    var preparationCalls = 0;
    final controller = ChatCubit(
      modelManager: modelManager,
      askQuestion: AskQuestionUseCase(
        ragRepository: _RagRepository(),
        llmService: _LlmService(Stream.value('Answer')),
      ),
      prepareKnowledgeBase: () {
        preparationCalls++;
        return knowledgePrepared.future;
      },
    );
    final states = <ChatState>[];
    final subscription = controller.stream.listen(states.add);

    await Future<void>.delayed(Duration.zero);
    expect(modelManager.state.status, ModelStatus.downloading);
    expect(controller.state.isPreparingKnowledge, isFalse);
    expect(controller.state.canSend, isFalse);
    expect(preparationCalls, 0);

    repository.finishDownload.complete();
    await Future<void>.delayed(Duration.zero);
    expect(modelManager.state.status, ModelStatus.loading);
    expect(controller.state.isPreparingKnowledge, isFalse);
    expect(preparationCalls, 0);

    repository.finishLoading.complete();
    await modelManager.ensureReady();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isPreparingKnowledge, isTrue);
    expect(controller.state.canSend, isFalse);
    expect(preparationCalls, 1);

    knowledgePrepared.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.knowledgeReady, isTrue);
    expect(controller.state.isPreparingKnowledge, isFalse);
    expect(controller.state.canSend, isTrue);
    expect(states.map((state) => state.modelState.status), [
      ModelStatus.notDownloaded,
      ModelStatus.downloading,
      ModelStatus.downloaded,
      ModelStatus.loading,
      ModelStatus.ready,
      ModelStatus.ready,
      ModelStatus.ready,
    ]);
    expect(states.map((state) => state.isPreparingKnowledge), [
      false,
      false,
      false,
      false,
      false,
      true,
      false,
    ]);
    expect(states.take(6).every((state) => !state.canSend), isTrue);

    await subscription.cancel();
    await controller.close();
    await modelManager.dispose();
  });

  test(
    'waits for a successful model retry before preparing knowledge',
    () async {
      final repository = _StagedModelRepository(failFirstDownload: true);
      final modelManager = LocalModelManager(repository);
      var preparationCalls = 0;
      final controller = ChatCubit(
        modelManager: modelManager,
        askQuestion: AskQuestionUseCase(
          ragRepository: _RagRepository(),
          llmService: _LlmService(Stream.value('Answer')),
        ),
        prepareKnowledgeBase: () async {
          preparationCalls++;
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(controller.state.modelState.status, ModelStatus.error);
      expect(controller.state.isPreparingKnowledge, isFalse);
      expect(preparationCalls, 0);

      final retry = controller.retryModelInitialization();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.modelState.status, ModelStatus.downloading);
      expect(preparationCalls, 0);
      repository.finishDownload.complete();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.modelState.status, ModelStatus.loading);
      expect(preparationCalls, 0);
      repository.finishLoading.complete();
      await retry;
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.knowledgeReady, isTrue);
      expect(preparationCalls, 1);

      await controller.close();
      await modelManager.dispose();
    },
  );

  test('prepares once when the model is already ready', () async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    var preparationCalls = 0;
    final controller = ChatCubit(
      modelManager: modelManager,
      askQuestion: AskQuestionUseCase(
        ragRepository: _RagRepository(),
        llmService: _LlmService(Stream.value('Answer')),
      ),
      prepareKnowledgeBase: () async {
        preparationCalls++;
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(controller.state.knowledgeReady, isTrue);
    expect(preparationCalls, 1);
    await modelManager.ensureReady();
    expect(preparationCalls, 1);

    await controller.close();
    await modelManager.dispose();
  });

  testWidgets('shows knowledge preparation after model loading, not download', (
    tester,
  ) async {
    final repository = _StagedModelRepository();
    final modelManager = LocalModelManager(repository);
    final knowledgePrepared = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          modelManager: modelManager,
          askQuestion: AskQuestionUseCase(
            ragRepository: _RagRepository(),
            llmService: _LlmService(Stream.value('Answer')),
          ),
          prepareKnowledgeBase: () => knowledgePrepared.future,
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Installing local AI model'), findsOneWidget);
    expect(find.textContaining('Preparing local knowledge'), findsNothing);

    repository.finishDownload.complete();
    await tester.pump();
    expect(find.textContaining('Preparing local knowledge'), findsNothing);

    repository.finishLoading.complete();
    await tester.pump();
    expect(find.textContaining('Preparing local knowledge'), findsOneWidget);

    knowledgePrepared.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Preparing local knowledge'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await modelManager.dispose();
  });

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
    final controller = ChatCubit(
      modelManager: modelManager,
      askQuestion: askQuestion,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          modelManager: modelManager,
          askQuestion: askQuestion,
          cubit: controller,
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
    await tester.runAsync(controller.close);
    await modelManager.dispose();
  });

  testWidgets('first rendered text waits for a frame after streamed text', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final response = StreamController<String>();
    final controller = ChatCubit(
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
    await tester.runAsync(controller.close);
    await modelManager.dispose();
  });

  test('progresses through streamed chunks and a controlled error', () async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final response = StreamController<String>();
    final controller = ChatCubit(
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
    await controller.close();
    await modelManager.dispose();
  });

  test('attaches grounded documents only when the answer finishes', () async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final response = StreamController<String>();
    final controller = ChatCubit(
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

    await controller.close();
    await modelManager.dispose();
  });

  test('keeps timing attached to each completed assistant message', () async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final secondResponse = StreamController<String>();
    final controller = ChatCubit(
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

    await controller.close();
    await modelManager.dispose();
  });

  test('clears visual and domain conversation history', () async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final history = InMemoryConversationHistory();
    final controller = ChatCubit(
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

    await controller.close();
    await modelManager.dispose();
  });

  test(
    'regenerates in place with fresh streaming, sources and timing',
    () async {
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      final history = InMemoryConversationHistory();
      final secondResponse = StreamController<String>();
      final controller = ChatCubit(
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
      await controller.close();
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
      final controller = ChatCubit(
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
      await controller.close();
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
      final controller = ChatCubit(
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
      await controller.close();
      await modelManager.dispose();
    },
  );

  test('retry rejects errors without a matching original question', () async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final controller = ChatCubit(
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
    await controller.close();
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

class _StagedModelRepository implements LocalModelRepository {
  _StagedModelRepository({this.failFirstDownload = false});

  final bool failFirstDownload;
  final finishDownload = Completer<void>();
  final finishLoading = Completer<void>();
  var downloadCalls = 0;

  @override
  Future<bool> isInstalled() async => false;

  @override
  Future<void> download({required void Function(int progress) onProgress}) {
    downloadCalls++;
    if (failFirstDownload && downloadCalls == 1) {
      throw StateError('Download failed');
    }
    return finishDownload.future;
  }

  @override
  Future<void> load() => finishLoading.future;
}

class _LlmService implements LocalLlmService {
  _LlmService(this.response);

  final Stream<String> response;
  var stopCalls = 0;
  var generateCalls = 0;

  @override
  Future<void> dispose() async {}

  @override
  Stream<String> generate(String prompt) {
    generateCalls++;
    return response;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
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
    String? exactMatchQuery,
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

class _DelayedRagRepository extends _RagRepository {
  final result = Completer<List<RagSearchResult>>();

  @override
  Future<List<RagSearchResult>> search({
    required String query,
    String? exactMatchQuery,
    int topK = 1,
    double threshold = 0,
  }) => result.future;
}
