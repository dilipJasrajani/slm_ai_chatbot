import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/app/app.dart';
import 'package:slm_ai_chatbot/features/chat/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_intent_router.dart';
import 'package:slm_ai_chatbot/features/chat/domain/chat_route.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/ai_chat_configuration.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/ai_chat_page.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/chat_controller.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/chat_models.dart';
import 'package:slm_ai_chatbot/features/llm/domain/local_llm_service.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_manager.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_repository.dart';
import 'package:slm_ai_chatbot/features/model/domain/model_status.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_search_result.dart';

void main() {
  testWidgets('welcome branding and suggestions use the existing send flow', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final response = StreamController<String>();
    final repository = _FakeRagRepository();
    var generations = 0;
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() {
            generations++;
            return response.stream;
          }),
          repository: repository,
        ),
      ),
    );
    expect(find.text('ViGuide AI'), findsOneWidget);
    expect(find.text('How can I help?'), findsOneWidget);
    expect(
      find.text('Ask a question using your local knowledge base.'),
      findsOneWidget,
    );
    expect(find.byType(ActionChip), findsNWidgets(2));
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
      isNull,
    );

    const prompt = 'How do I troubleshoot a network connection?';
    await tester.tap(find.text(prompt));
    await tester.pump();
    await tester.pump();
    expect(find.text(prompt), findsOneWidget);
    expect(find.text('How can I help?'), findsNothing);
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    expect(repository.searchCount, 1);
    expect(generations, 1);

    response.add('Check the connection.');
    await tester.pump();
    await response.close();
    await tester.pumpAndSettle();
    expect(find.text('Check the connection.'), findsOneWidget);
    expect(find.text('Sources · 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear conversation'));
    await tester.pump();
    expect(find.text('ViGuide AI'), findsOneWidget);
    expect(find.text('How can I help?'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(2));
    expect(find.text('Check the connection.'), findsNothing);
    await modelManager.dispose();
  });

  testWidgets('custom assistant image and welcome copy are used throughout', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final logo = MemoryImage(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mP8/x8AAwMCAO+nS90AAAAASUVORK5CYII=',
      ),
    );
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() => Stream.value('Welcome!')),
          intentRouter: const _FixedChatIntentRouter(ChatRoute.chat),
        ),
        chatConfiguration: AiChatConfiguration(
          assistantName: 'Koko AI',
          assistantAvatar: logo,
          welcomeTitle: 'How can we help?',
          welcomeMessage: 'Ask about your device or error code.',
          suggestions: const ['What can you help me with?'],
        ),
      ),
    );
    expect(find.text('Koko AI'), findsOneWidget);
    expect(find.text('How can we help?'), findsOneWidget);
    expect(find.text('Ask about your device or error code.'), findsOneWidget);
    expect(find.byType(ActionChip), findsOneWidget);
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
      same(logo),
    );
    await tester.tap(find.text('What can you help me with?'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome!'), findsOneWidget);
    expect(find.text('Koko AI'), findsNothing);
    expect(
      tester.widget<AiAvatar>(find.byType(AiAvatar)).assistantName,
      'Koko AI',
    );
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
      same(logo),
    );
    expect(tester.takeException(), isNull);
    await modelManager.dispose();
  });

  testWidgets('empty suggestions and description take no space', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(_FakeLlmService(() => Stream.value('OK'))),
        chatConfiguration: const AiChatConfiguration(
          welcomeMessage: '',
          suggestions: [],
        ),
      ),
    );
    expect(find.text('ViGuide AI'), findsOneWidget);
    expect(find.text('How can I help?'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    expect(tester.takeException(), isNull);
    await modelManager.dispose();
  });

  testWidgets('long branding and prompts wrap at narrow and wide widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    tester.view.physicalSize = const Size(320, 640);
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    const name =
        'A long assistant name for technical support across many devices';
    const prompt =
        'Explain how to troubleshoot a device with an unusually long network '
        'connection description and several related error codes';
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(_FakeLlmService(() => Stream.value('OK'))),
        chatConfiguration: const AiChatConfiguration(
          assistantName: name,
          welcomeTitle: 'A helpful and approachable welcome for every device',
          welcomeMessage: '',
          suggestions: [prompt],
        ),
      ),
    );

    for (final size in [
      const Size(320, 640),
      const Size(400, 860),
      const Size(900, 1100),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(find.text(name), findsOneWidget);
      expect(find.text(prompt), findsOneWidget);
      expect(
        tester.getSize(find.byType(ActionChip)).width,
        lessThan(size.width),
      );
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(320, 640);
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getBottomRight(find.byType(TextField)).dy, lessThan(420));
    await modelManager.dispose();
  });

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
    expect(find.text('Qwen3 0.6B · Local'), findsOneWidget);
    expect(find.textContaining('GPU'), findsNothing);

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
    expect(find.textContaining('Generated in'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    firstResponse.add('Check ');
    await tester.pump();
    expect(find.text('Thinking…'), findsNothing);
    expect(find.text('Check '), findsOneWidget);
    expect(find.textContaining('Generated in'), findsNothing);
    expect(find.textContaining('Sources'), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    final answerOpacity = find.ancestor(
      of: find.text('Check '),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(answerOpacity).opacity, 1);

    firstResponse.add('the connection.');
    await tester.pump();
    expect(find.text('Check the connection.'), findsOneWidget);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.text('Check the connection.'),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      1,
    );

    firstResponse.addError(Exception('generation failed'));
    await tester.pump();
    expect(
      find.text('Unable to generate an answer with the local AI model.'),
      findsOneWidget,
    );
    expect(find.textContaining('Generated in'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Recovered.'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Generated in \d+\.\d{2}s$')),
      findsOneWidget,
    );
    expect(find.text('Sources · 1'), findsOneWidget);
    expect(attempts, 2);

    unawaited(firstResponse.close());
    await modelManager.dispose();
  });

  testWidgets('model label and actual backend are optional and configurable', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final askQuestion = _askQuestion(_FakeLlmService(() => Stream.value('OK')));

    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: askQuestion,
        runtimeBackendLabel: () => 'GPU',
      ),
    );
    expect(find.text('Qwen3 0.6B · Local · GPU'), findsOneWidget);

    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: askQuestion,
        chatConfiguration: const AiChatConfiguration(
          modelLabel: 'Private model',
          showRuntimeBackend: false,
        ),
        runtimeBackendLabel: () => 'GPU',
      ),
    );
    expect(find.text('Private model'), findsOneWidget);
    expect(find.textContaining('GPU'), findsNothing);

    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: askQuestion,
        chatConfiguration: const AiChatConfiguration(showModelLabel: false),
        runtimeBackendLabel: () => 'GPU',
      ),
    );
    expect(find.textContaining('Qwen3'), findsNothing);
    expect(find.textContaining('GPU'), findsNothing);
    await modelManager.dispose();
  });

  testWidgets('grounded sources stay compact until generation completes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.physicalSize = const Size(320, 640);
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final response = StreamController<String>();
    final repository = _FakeRagRepository([
      const RagSearchResult(
        document: KnowledgeDocument(
          id: 'error-e123',
          title: 'Device network connection guide',
          content: 'Verify stored Wi-Fi credentials.',
          metadata: {'code': 'E123', 'type': 'error'},
        ),
        similarity: 1,
      ),
      const RagSearchResult(
        document: KnowledgeDocument(
          id: 'guide-2',
          title: 'Network troubleshooting guide',
          content: 'Restart the device and retry the connection.',
          metadata: {},
        ),
        similarity: .9,
      ),
    ]);
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() => response.stream),
          repository: repository,
          intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
        ),
        chatConfiguration: const AiChatConfiguration(
          sourceSectionLabel: 'References',
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Network connection help');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.textContaining('Generated in'), findsNothing);
    expect(find.textContaining('References'), findsNothing);

    response.add('Check ');
    await tester.pump();
    expect(find.text('Check '), findsOneWidget);
    expect(find.textContaining('Generated in'), findsNothing);
    expect(find.textContaining('References'), findsNothing);

    response.add('Wi-Fi credentials.');
    await tester.pump();
    expect(find.textContaining('Generated in'), findsNothing);
    expect(find.textContaining('References'), findsNothing);
    await response.close();
    await tester.pump();
    await tester.pump();
    expect(repository.searchCount, 1);
    expect(
      find.textContaining(RegExp(r'^Generated in \d+\.\d{2}s$')),
      findsOneWidget,
    );
    expect(find.text('References · 2'), findsOneWidget);
    expect(find.text('E123 — Device network connection guide'), findsOneWidget);
    expect(find.text('Network troubleshooting guide'), findsOneWidget);
    expect(find.text('Verify stored Wi-Fi credentials.'), findsNothing);
    expect(find.textContaining('Restart the device'), findsNothing);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.textContaining('error-e123'), findsNothing);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(400, 860);
    await tester.pump();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(900, 1100);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await modelManager.dispose();
  });

  testWidgets('CHAT and ungrounded answers never display sources', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final repository = _FakeRagRepository();
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() => Stream.value('Hello!')),
          repository: repository,
          intentRouter: const _FixedChatIntentRouter(ChatRoute.chat),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Hi');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Hello!'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Generated in \d+\.\d{2}s$')),
      findsOneWidget,
    );
    expect(find.textContaining('Sources'), findsNothing);
    expect(repository.searchCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    final emptyRepository = _FakeRagRepository(const []);
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() => Stream.value('unused')),
          repository: emptyRepository,
          intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Unrelated question');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Generated in'), findsNothing);
    expect(find.textContaining('Sources'), findsNothing);
    expect(emptyRepository.searchCount, 1);
    await modelManager.dispose();
  });

  testWidgets('source visibility can be disabled independently', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() => Stream.value('Check Wi-Fi.')),
          intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
        ),
        chatConfiguration: const AiChatConfiguration(showLocalSources: false),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Network connection help');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Check Wi-Fi.'), findsOneWidget);
    expect(find.textContaining('Sources'), findsNothing);
    expect(
      find.textContaining(RegExp(r'^Generated in \d+\.\d{2}s$')),
      findsOneWidget,
    );
    await modelManager.dispose();
  });

  testWidgets('generation time can be hidden without hiding sources', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() => Stream.value('Check Wi-Fi.')),
          intentRouter: const _FixedChatIntentRouter(ChatRoute.knowledge),
        ),
        chatConfiguration: const AiChatConfiguration(showGenerationTime: false),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Network connection help');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Check Wi-Fi.'), findsOneWidget);
    expect(find.text('Sources · 1'), findsOneWidget);
    expect(find.textContaining('Generated in'), findsNothing);
    await modelManager.dispose();
  });

  testWidgets('generation time label is customizable', (tester) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() => Stream.value('Hello!')),
          intentRouter: const _FixedChatIntentRouter(ChatRoute.chat),
        ),
        chatConfiguration: const AiChatConfiguration(
          generationTimeLabel: 'Completed in',
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Hi');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp(r'^Completed in \d+\.\d{2}s$')),
      findsOneWidget,
    );
    expect(find.textContaining('Sources'), findsNothing);
    await modelManager.dispose();
  });

  testWidgets('chat and composer stay readable across viewport sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    tester.view.physicalSize = const Size(320, 640);
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final response = StreamController<String>();
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(_FakeLlmService(() => response.stream)),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'A long multiline question\nabout a device and its network connection',
    );
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    response.add(
      'A long answer that should wrap naturally on a narrow phone and '
      'remain readable instead of stretching across a tablet screen.',
    );
    await tester.pump();

    for (final size in [
      const Size(320, 640),
      const Size(400, 860),
      const Size(900, 1100),
      const Size(720, 360),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('message-0'))).width,
        lessThanOrEqualTo(720),
      );
      expect(
        tester.getSize(find.byType(TextField)).width,
        lessThanOrEqualTo(720),
      );
      expect(
        tester.getTopLeft(find.byType(TextField)).dy,
        lessThan(size.height),
      );
    }

    tester.view.physicalSize = const Size(400, 860);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getBottomRight(find.byType(TextField)).dy, lessThan(600));

    await response.close();
    await modelManager.dispose();
  });

  testWidgets('custom theme styles welcome, messages, composer and metadata', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    const chatTheme = AiChatTheme(
      primaryColor: Colors.amber,
      accentColor: Colors.teal,
      userBubbleColor: Colors.yellow,
      assistantBubbleColor: Colors.black,
    );
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() => Stream.value('Check the connection.')),
        ),
        chatConfiguration: const AiChatConfiguration(
          assistantName: 'Support AI',
          suggestions: ['Network connection help'],
        ),
        chatTheme: chatTheme,
        runtimeBackendLabel: () => 'GPU',
      ),
    );
    expect(find.text('Support AI'), findsOneWidget);
    expect(find.text('How can I help?'), findsOneWidget);
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundColor,
      Colors.amber,
    );
    final chip = tester.widget<ActionChip>(find.byType(ActionChip));
    expect(chip.side?.color, Colors.teal);
    expect(chip.backgroundColor, Colors.white);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Send message',
            ),
          )
          .style!
          .backgroundColor!
          .resolve({}),
      Colors.amber,
    );
    expect(
      (tester
                  .widget<TextField>(find.byType(TextField))
                  .decoration!
                  .focusedBorder!
              as OutlineInputBorder)
          .borderSide
          .color,
      Colors.amber,
    );
    expect(find.text('Qwen3 0.6B · Local · GPU'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Qwen3 0.6B · Local · GPU')).style?.color,
      chatTheme.backgroundTextColor.withValues(alpha: .75),
    );

    await tester.tap(find.text('Network connection help'));
    await tester.pumpAndSettle();
    expect(find.text('How can I help?'), findsNothing);
    expect(find.text('Check the connection.'), findsOneWidget);
    expect(find.text('Sources · 1'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Generated in \d+\.\d{2}s$')),
      findsOneWidget,
    );
    final userText = tester.widget<Text>(find.text('Network connection help'));
    final assistantText = tester.widget<Text>(
      find.text('Check the connection.'),
    );
    expect(userText.style?.color, const Color(0xFF1A1C20));
    expect(assistantText.style?.color, Colors.white);
    final userBubble = tester
        .widgetList<Container>(
          find.ancestor(
            of: find.text('Network connection help'),
            matching: find.byType(Container),
          ),
        )
        .firstWhere((container) => container.decoration is BoxDecoration);
    final assistantBubble = tester
        .widgetList<Container>(
          find.ancestor(
            of: find.text('Check the connection.'),
            matching: find.byType(Container),
          ),
        )
        .firstWhere((container) => container.decoration is BoxDecoration);
    expect((userBubble.decoration! as BoxDecoration).color, Colors.yellow);
    expect((assistantBubble.decoration! as BoxDecoration).color, Colors.black);
    expect(
      tester.widget<Text>(find.text('Sources · 1')).style?.color,
      chatTheme.backgroundTextColor.withValues(alpha: .75),
    );
    expect(tester.takeException(), isNull);
    await modelManager.dispose();
  });

  testWidgets(
    'dark host colors update existing messages without losing state',
    (tester) async {
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      final askQuestion = _askQuestion(
        _FakeLlmService(() => Stream.value('Dark mode answer.')),
        intentRouter: const _FixedChatIntentRouter(ChatRoute.chat),
      );
      final darkTheme = ThemeData.dark();
      Widget app(ThemeData theme) => MaterialApp(
        theme: theme,
        home: AiChatPage(modelManager: modelManager, askQuestion: askQuestion),
      );

      await tester.pumpWidget(app(ThemeData.light()));
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        const AiChatTheme().backgroundColor,
      );
      await tester.enterText(find.byType(TextField), 'Hi');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('Dark mode answer.'), findsOneWidget);

      await tester.pumpWidget(app(darkTheme));
      await tester.pumpAndSettle();
      expect(find.text('Dark mode answer.'), findsOneWidget);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        darkTheme.colorScheme.surface,
      );
      expect(
        tester.widget<AiAvatar>(find.byType(AiAvatar)).theme.primaryColor,
        darkTheme.colorScheme.primary,
      );
      expect(
        tester.widget<Text>(find.text('Dark mode answer.')).style?.color,
        Colors.white,
      );
      final answerBubble = tester
          .widgetList<Container>(
            find.ancestor(
              of: find.text('Dark mode answer.'),
              matching: find.byType(Container),
            ),
          )
          .firstWhere((container) => container.decoration is BoxDecoration);
      expect(
        (answerBubble.decoration! as BoxDecoration).color,
        darkTheme.colorScheme.surfaceContainerHighest,
      );
      expect(find.text('Sources · 1'), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.textContaining(RegExp(r'^Generated in \d+\.\d{2}s$')),
            )
            .style
            ?.color,
        Colors.white.withValues(alpha: .75),
      );
      expect(tester.takeException(), isNull);
      await modelManager.dispose();
    },
  );

  testWidgets('themed welcome stays responsive on narrow and wide screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.physicalSize = const Size(320, 640);
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    const prompt =
        'Explain a device connection error with a very long description '
        'that wraps across several lines';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AiChatPage(
          modelManager: modelManager,
          askQuestion: _askQuestion(_FakeLlmService(() => Stream.value('OK'))),
          chatTheme: const AiChatTheme(primaryColor: Colors.amber),
          configuration: const AiChatConfiguration(
            assistantName:
                'A long technical support assistant name for every device',
            suggestions: [prompt],
          ),
        ),
      ),
    );
    for (final size in [
      const Size(320, 640),
      const Size(400, 860),
      const Size(900, 1100),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(find.text(prompt), findsOneWidget);
      expect(
        tester.getSize(find.byType(ActionChip)).width,
        lessThan(size.width),
      );
      expect(tester.takeException(), isNull);
    }
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      ThemeData.dark().colorScheme.surface,
    );
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundColor,
      Colors.amber,
    );
    final darkChip = tester.widget<ActionChip>(find.byType(ActionChip));
    expect(darkChip.side?.color, ThemeData.dark().colorScheme.secondary);
    expect(darkChip.labelStyle?.color, Colors.white);
    await tester.tap(find.text(prompt));
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(prompt)).style?.color,
      const Color(0xFF1A1C20),
    );
    await modelManager.dispose();
  });

  testWidgets('Copy appears after completion and copies only the full answer', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final response = StreamController<String>();
    const answer =
        'The device cannot connect.\n\nPossible causes:\n'
        '- Network unavailable\n- Invalid configuration\n- Device offline';
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(_FakeLlmService(() => response.stream)),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Network connection help');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsNothing);

    response.add('The device cannot connect.\n\n');
    await tester.pump();
    expect(find.byTooltip('Copy response'), findsNothing);
    response.add(
      'Possible causes:\n'
      '- Network unavailable\n- Invalid configuration\n- Device offline',
    );
    await tester.pump();
    expect(find.text(answer), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsNothing);

    await response.close();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.text('Network connection help'), findsOneWidget);
    expect(find.text('Sources · 1'), findsOneWidget);
    expect(find.text('Device network connection guide'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Generated in \d+\.\d{2}s$')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Copy response'));
    await tester.pump();
    expect(clipboardText, answer);
    expect((await Clipboard.getData('text/plain'))?.text, answer);
    expect(find.byTooltip('Copied'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.byTooltip('Copied'), findsNothing);
    await modelManager.dispose();
  });

  testWidgets('Copy excludes user, streaming, error and empty messages', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final askQuestion = _askQuestion(
      _FakeLlmService(() => Stream.value('unused')),
    );
    final controller = _MessagesController(
      modelManager: modelManager,
      askQuestion: askQuestion,
      messages: const [
        ChatMessage(id: 'user', author: ChatAuthor.user, text: 'Question'),
        ChatMessage(
          id: 'thinking',
          author: ChatAuthor.assistant,
          text: '',
          isStreaming: true,
        ),
        ChatMessage(
          id: 'stream',
          author: ChatAuthor.assistant,
          text: 'Partial',
          isStreaming: true,
        ),
        ChatMessage(
          id: 'error',
          author: ChatAuthor.assistant,
          text: 'Model failed',
          isError: true,
        ),
        ChatMessage(id: 'empty', author: ChatAuthor.assistant, text: ''),
        ChatMessage(id: 'answer', author: ChatAuthor.assistant, text: 'Done'),
      ],
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
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          modelManager: modelManager,
          askQuestion: askQuestion,
          controller: controller,
          configuration: const AiChatConfiguration(showCopyAction: false),
        ),
      ),
    );
    expect(find.byTooltip('Copy response'), findsNothing);
    expect(find.byTooltip('Copied'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await modelManager.dispose();
  });

  testWidgets('Copy failure is visible and can be retried', (tester) async {
    var fail = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData' && fail) {
          throw PlatformException(code: 'clipboard_unavailable');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final askQuestion = _askQuestion(
      _FakeLlmService(() => Stream.value('unused')),
    );
    final controller = _MessagesController(
      modelManager: modelManager,
      askQuestion: askQuestion,
      messages: const [
        ChatMessage(id: 'answer', author: ChatAuthor.assistant, text: 'Answer'),
      ],
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
    await tester.tap(find.byTooltip('Copy response'));
    await tester.pump();
    expect(find.byTooltip('Copy failed'), findsOneWidget);
    expect(find.byTooltip('Copied'), findsNothing);
    fail = false;
    await tester.tap(find.byTooltip('Copy failed'));
    await tester.pump();
    expect(find.byTooltip('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byTooltip('Copy response'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await modelManager.dispose();
  });

  testWidgets('Copy remains usable in dark mode at phone and tablet widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.physicalSize = const Size(320, 640);
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final askQuestion = _askQuestion(
      _FakeLlmService(() => Stream.value('unused')),
    );
    final controller = _MessagesController(
      modelManager: modelManager,
      askQuestion: askQuestion,
      messages: const [
        ChatMessage(
          id: 'answer',
          author: ChatAuthor.assistant,
          text: 'A long answer about device troubleshooting and networking.',
          generationDuration: Duration(seconds: 2),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AiChatPage(
          modelManager: modelManager,
          askQuestion: askQuestion,
          controller: controller,
          chatTheme: const AiChatTheme(primaryColor: Colors.amber),
        ),
      ),
    );
    for (final size in [
      const Size(320, 640),
      const Size(400, 860),
      const Size(900, 1100),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(find.byTooltip('Copy response'), findsOneWidget);
      expect(find.text('Generated in 2.00s'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await modelManager.dispose();
  });

  testWidgets(
    'Regenerate streams into one bubble with fresh sources and Copy',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.physicalSize = const Size(320, 640);
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<Object?, Object?>)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      final repository = _FakeRagRepository();
      final updatedResponse = StreamController<String>();
      var generationCount = 0;
      await tester.pumpWidget(
        MyApp(
          modelManager: modelManager,
          askQuestion: _askQuestion(
            _FakeLlmService(() {
              generationCount++;
              return generationCount == 1
                  ? Stream.value('Previous answer.')
                  : updatedResponse.stream;
            }),
            repository: repository,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Network connection help');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('Previous answer.'), findsOneWidget);
      expect(find.text('Sources · 1'), findsOneWidget);
      expect(find.text('Device network connection guide'), findsOneWidget);
      expect(find.byTooltip('Regenerate response'), findsOneWidget);
      repository.results = const [
        RagSearchResult(
          document: KnowledgeDocument(
            id: 'new-guide',
            title: 'Updated network connection guide',
            content: 'Check the network connection and retry.',
            metadata: {'code': 'E123'},
          ),
          similarity: 1,
        ),
      ];

      await tester.tap(find.byTooltip('Regenerate response'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Previous answer.'), findsNothing);
      expect(find.text('Thinking…'), findsOneWidget);
      expect(find.byTooltip('Copy response'), findsNothing);
      expect(find.byTooltip('Regenerate response'), findsNothing);
      expect(find.text('Network connection help'), findsOneWidget);
      expect(find.textContaining('Generated in'), findsNothing);
      expect(find.textContaining('Sources'), findsNothing);
      expect(repository.searchCount, 2);
      expect(generationCount, 2);

      updatedResponse.add('Updated ');
      await tester.pump();
      expect(find.text('Updated '), findsOneWidget);
      expect(find.text('Thinking…'), findsNothing);
      expect(find.byTooltip('Copy response'), findsNothing);
      updatedResponse.add('answer.\nCheck the connection.');
      await tester.pump();
      await updatedResponse.close();
      await tester.pumpAndSettle();
      expect(
        find.text('Updated answer.\nCheck the connection.'),
        findsOneWidget,
      );
      expect(find.text('Previous answer.'), findsNothing);
      expect(find.text('Network connection help'), findsOneWidget);
      expect(
        find.text('E123 — Updated network connection guide'),
        findsOneWidget,
      );
      expect(find.text('Device network connection guide'), findsNothing);
      expect(
        find.textContaining(RegExp(r'^Generated in \d+\.\d{2}s$')),
        findsOneWidget,
      );
      expect(find.byTooltip('Regenerate response'), findsOneWidget);
      expect(find.byTooltip('Copy response'), findsOneWidget);
      await tester.tap(find.byTooltip('Copy response'));
      await tester.pump();
      expect(clipboardText, 'Updated answer.\nCheck the connection.');

      for (final size in [
        const Size(320, 640),
        const Size(400, 860),
        const Size(900, 1100),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await modelManager.dispose();
    },
  );

  testWidgets('Regenerate eligibility and configuration leave Copy intact', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.physicalSize = const Size(900, 1100);
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final askQuestion = _askQuestion(
      _FakeLlmService(() => Stream.value('unused')),
    );
    const firstTurns = [
      ChatMessage(
        id: 'user-1',
        author: ChatAuthor.user,
        text: 'First question',
      ),
      ChatMessage(
        id: 'answer-1',
        author: ChatAuthor.assistant,
        text: 'First answer',
        question: 'First question',
      ),
      ChatMessage(
        id: 'user-2',
        author: ChatAuthor.user,
        text: 'Second question',
      ),
      ChatMessage(
        id: 'answer-2',
        author: ChatAuthor.assistant,
        text: 'Second answer',
        question: 'Second question',
      ),
    ];
    const thirdUser = ChatMessage(
      id: 'user-3',
      author: ChatAuthor.user,
      text: 'Third question',
    );
    final controller = _MessagesController(
      modelManager: modelManager,
      askQuestion: askQuestion,
      messages: firstTurns,
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
    expect(find.byTooltip('Regenerate response'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsNWidgets(2));
    expect(find.text('First answer'), findsOneWidget);
    expect(find.text('Second answer'), findsOneWidget);

    controller.setMessages([...firstTurns, thirdUser]);
    await tester.pump();
    expect(find.byTooltip('Regenerate response'), findsNothing);
    expect(find.byTooltip('Copy response'), findsNWidgets(2));

    controller.setMessages([
      ...firstTurns,
      thirdUser,
      const ChatMessage(
        id: 'answer-3',
        author: ChatAuthor.assistant,
        text: '',
        question: 'Third question',
        isStreaming: true,
      ),
    ]);
    await tester.pump();
    expect(find.byTooltip('Regenerate response'), findsNothing);
    expect(find.byTooltip('Copy response'), findsNWidgets(2));

    controller.setMessages([
      ...firstTurns,
      thirdUser,
      const ChatMessage(
        id: 'answer-3',
        author: ChatAuthor.assistant,
        text: 'Partial',
        question: 'Third question',
        isStreaming: true,
      ),
    ]);
    await tester.pump();
    expect(find.byTooltip('Regenerate response'), findsNothing);
    expect(find.byTooltip('Copy response'), findsNWidgets(2));

    controller.setMessages([
      ...firstTurns,
      thirdUser,
      const ChatMessage(
        id: 'answer-3',
        author: ChatAuthor.assistant,
        text: 'Failed',
        question: 'Third question',
        isError: true,
      ),
    ]);
    await tester.pump();
    expect(find.byTooltip('Regenerate response'), findsNothing);
    expect(find.byTooltip('Copy response'), findsNWidgets(2));

    controller.setMessages([
      ...firstTurns,
      thirdUser,
      const ChatMessage(
        id: 'answer-3',
        author: ChatAuthor.assistant,
        text: '',
        question: 'Third question',
      ),
    ]);
    await tester.pump();
    expect(find.byTooltip('Regenerate response'), findsNothing);
    expect(find.byTooltip('Copy response'), findsNWidgets(2));

    controller.setMessages([
      ...firstTurns,
      thirdUser,
      const ChatMessage(
        id: 'answer-3',
        author: ChatAuthor.assistant,
        text: 'Third answer',
        question: 'Third question',
      ),
    ]);
    await tester.pump();
    expect(find.byTooltip('Regenerate response'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsNWidgets(3));

    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          modelManager: modelManager,
          askQuestion: askQuestion,
          controller: controller,
          configuration: const AiChatConfiguration(showRegenerateAction: false),
        ),
      ),
    );
    expect(find.byTooltip('Regenerate response'), findsNothing);
    expect(find.byTooltip('Copy response'), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await modelManager.dispose();
  });

  testWidgets(
    'Regenerate is unavailable during generation and restores errors',
    (tester) async {
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      final secondResponse = StreamController<String>();
      var call = 0;
      await tester.pumpWidget(
        MyApp(
          modelManager: modelManager,
          askQuestion: _askQuestion(
            _FakeLlmService(() {
              call++;
              return switch (call) {
                1 => Stream.value('First answer'),
                2 => secondResponse.stream,
                3 => Stream<String>.error(StateError('Unavailable')),
                _ => Stream.value('Recovered answer'),
              };
            }),
            intentRouter: const _FixedChatIntentRouter(ChatRoute.chat),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Hi');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Regenerate response'), findsOneWidget);
      expect(find.textContaining('Sources'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Follow up');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      expect(find.byTooltip('Regenerate response'), findsNothing);
      expect(find.byTooltip('Copy response'), findsOneWidget);
      expect(find.text('Thinking…'), findsOneWidget);
      secondResponse.add('Second answer');
      await tester.pump();
      await secondResponse.close();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Regenerate response'), findsOneWidget);
      expect(find.byTooltip('Copy response'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Regenerate response'));
      await tester.pumpAndSettle();
      expect(find.text('Second answer'), findsOneWidget);
      expect(
        find.text('Local AI model is not installed or could not be loaded.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Copy response'), findsNWidgets(2));
      expect(find.text('First answer'), findsOneWidget);
      expect(find.byTooltip('Regenerate response'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Regenerate response'));
      await tester.pumpAndSettle();
      expect(find.text('Recovered answer'), findsOneWidget);
      expect(find.text('Second answer'), findsNothing);
      expect(find.textContaining('Sources'), findsNothing);
      expect(
        find.textContaining(RegExp(r'^Generated in \d+\.\d{2}s$')),
        findsNWidgets(2),
      );
      expect(find.byTooltip('Copy response'), findsNWidgets(2));
      expect(find.byTooltip('Regenerate response'), findsOneWidget);
      await modelManager.dispose();
    },
  );

  testWidgets('incomplete Markdown stays plain until the stream finishes', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final response = StreamController<String>();
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() => response.stream),
          intentRouter: const _FixedChatIntentRouter(ChatRoute.chat),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Show a code example');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(find.text('Thinking…'), findsOneWidget);
    const partial = '## Example\n\n```dart\nfinal value =';
    response.add(partial);
    await tester.pump();
    expect(find.text(partial), findsOneWidget);
    expect(find.byTooltip('Copy code'), findsNothing);
    expect(find.byTooltip('Copy response'), findsNothing);
    expect(find.text('Thinking…'), findsNothing);
    response.add(' 10;\n```');
    await tester.pump();
    expect(find.byTooltip('Copy code'), findsNothing);
    await response.close();
    await tester.pumpAndSettle();
    expect(find.text('Example'), findsOneWidget);
    expect(find.text('final value = 10;'), findsOneWidget);
    expect(find.byTooltip('Copy code'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.byTooltip('Regenerate response'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Generated in \d+\.\d{2}s$')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await modelManager.dispose();
  });

  testWidgets(
    'rich response Copy and latest-only Regenerate stay independent',
    (tester) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<Object?, Object?>)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      final askQuestion = _askQuestion(
        _FakeLlmService(() => Stream.value('unused')),
      );
      const firstAnswer = '## First\n\n```dart\nfinal first = 1;\n```';
      const secondAnswer = '## Second\n\n```json\n{"second": 2}\n```';
      final controller = _MessagesController(
        modelManager: modelManager,
        askQuestion: askQuestion,
        messages: const [
          ChatMessage(id: 'user-1', author: ChatAuthor.user, text: 'One'),
          ChatMessage(
            id: 'answer-1',
            author: ChatAuthor.assistant,
            text: firstAnswer,
            question: 'One',
          ),
          ChatMessage(id: 'user-2', author: ChatAuthor.user, text: 'Two'),
          ChatMessage(
            id: 'answer-2',
            author: ChatAuthor.assistant,
            text: secondAnswer,
            question: 'Two',
          ),
        ],
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
      expect(find.byTooltip('Copy code'), findsNWidgets(2));
      expect(find.byTooltip('Copy response'), findsNWidgets(2));
      expect(find.byTooltip('Regenerate response'), findsOneWidget);
      await tester.tap(find.byTooltip('Copy response').first);
      await tester.pump();
      expect(clipboardText, firstAnswer);
      await tester.tap(find.byTooltip('Copy code').last);
      await tester.pump();
      expect(clipboardText, '{"second": 2}');
      expect(find.byTooltip('Regenerate response'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await modelManager.dispose();
    },
  );

  testWidgets(
    'long code stays inside chat at phone, tablet and keyboard sizes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });
      tester.view.physicalSize = const Size(280, 640);
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      final askQuestion = _askQuestion(
        _FakeLlmService(() => Stream.value('unused')),
      );
      final code = 'final value = "${'x' * 220}";';
      final controller = _MessagesController(
        modelManager: modelManager,
        askQuestion: askQuestion,
        messages: [
          const ChatMessage(
            id: 'user',
            author: ChatAuthor.user,
            text: '## Literal user text\n\n- Not a list',
          ),
          ChatMessage(
            id: 'answer',
            author: ChatAuthor.assistant,
            text: '## Example\n\n- Step one\n- Step two\n\n```dart\n$code\n```',
            question: 'Show an example',
          ),
        ],
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
      expect(find.text('## Literal user text\n\n- Not a list'), findsOneWidget);
      for (final size in [
        const Size(280, 640),
        const Size(400, 860),
        const Size(900, 1100),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();
        expect(find.text(code), findsOneWidget);
        expect(find.byTooltip('Copy code'), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('answer'))).width,
          lessThanOrEqualTo(size.width),
        );
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(280, 640);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getBottomRight(find.byType(TextField)).dy, lessThan(430));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await modelManager.dispose();
    },
  );

  testWidgets('Retry only appears on failed responses when enabled', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final askQuestion = _askQuestion(
      _FakeLlmService(() => Stream.value('unused')),
    );
    final controller = _MessagesController(
      modelManager: modelManager,
      askQuestion: askQuestion,
      messages: const [
        ChatMessage(id: 'user', author: ChatAuthor.user, text: 'Question'),
        ChatMessage(
          id: 'error',
          author: ChatAuthor.assistant,
          text: 'Unable to search the local knowledge base.',
          isError: true,
          question: 'Question',
        ),
        ChatMessage(id: 'empty', author: ChatAuthor.assistant, text: ''),
        ChatMessage(
          id: 'streaming',
          author: ChatAuthor.assistant,
          text: 'Partial',
          isStreaming: true,
          question: 'Next question',
        ),
        ChatMessage(
          id: 'completed',
          author: ChatAuthor.assistant,
          text: 'Completed answer',
          question: 'Last question',
        ),
      ],
    );
    Widget app(bool allowRetry) => MaterialApp(
      theme: ThemeData.dark(),
      home: AiChatPage(
        modelManager: modelManager,
        askQuestion: askQuestion,
        controller: controller,
        configuration: AiChatConfiguration(showRetryAction: allowRetry),
      ),
    );
    await tester.pumpWidget(app(true));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.byTooltip('Regenerate response'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.ancestor(
              of: find.text('Retry'),
              matching: find.byWidgetPredicate(
                (widget) => widget is TextButton,
              ),
            ),
          )
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(app(false));
    expect(find.text('Retry'), findsNothing);
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.byTooltip('Regenerate response'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await modelManager.dispose();
  });

  testWidgets('retrieval Retry reroutes in place with Markdown and sources', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final secondSearch = Completer<void>();
    final repository = _RetryableRagRepository(secondSearch.future);
    final router = _CountingChatIntentRouter();
    var generationCount = 0;
    const answer =
        '## Fix\n\n- Check `E123`\n\n```dart\nfinal fixed = true;\n```';
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() {
            generationCount++;
            return Stream.value(answer);
          }),
          repository: repository,
          intentRouter: router,
        ),
      ),
    );
    const question = 'How do I troubleshoot a network connection?';
    await tester.enterText(find.byType(TextField), question);
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to search the local knowledge base.'),
      findsOneWidget,
    );
    expect(find.textContaining('Exception:'), findsNothing);
    expect(find.text(question), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsNothing);
    expect(find.byTooltip('Regenerate response'), findsNothing);
    expect(generationCount, 0);

    final retryButton = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Retry'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      ),
    );
    await tester.tap(find.text('Retry'));
    retryButton.onPressed!();
    await tester.pump();
    await tester.pump();
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Send message',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.text(question), findsOneWidget);
    expect(find.byType(AiAvatar), findsOneWidget);
    expect(repository.attempts, 2);
    secondSearch.complete();
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Fix'), findsOneWidget);
    expect(find.text('final fixed = true;'), findsOneWidget);
    expect(find.byTooltip('Copy code'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.byTooltip('Regenerate response'), findsOneWidget);
    expect(find.text('Sources · 1'), findsOneWidget);
    expect(find.text('Device network connection guide'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Generated in \d+\.\d{2}s$')),
      findsOneWidget,
    );
    expect(find.text(question), findsOneWidget);
    expect(find.byType(AiAvatar), findsOneWidget);
    expect(router.calls, 2);
    expect(generationCount, 1);
    await tester.tap(find.byTooltip('Copy response'));
    await tester.pump();
    expect(clipboardText, answer);
    await tester.tap(find.byTooltip('Copy code'));
    await tester.pump();
    expect(clipboardText, 'final fixed = true;');
    expect(tester.takeException(), isNull);
    await modelManager.dispose();
  });

  testWidgets('failed Retry restores a friendly error and can be repeated', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    var attempts = 0;
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() {
            attempts++;
            return switch (attempts) {
              1 => Stream<String>.error(
                StateError('BackendInitException: secret native details'),
              ),
              2 => Stream<String>.error(
                Exception('PlatformException: stack trace'),
              ),
              _ => Stream.value('Recovered answer'),
            };
          }),
          intentRouter: const _FixedChatIntentRouter(ChatRoute.chat),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Original question');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(
      find.text('Local AI model is not installed or could not be loaded.'),
      findsOneWidget,
    );
    expect(find.textContaining('BackendInitException'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to generate an answer with the local AI model.'),
      findsOneWidget,
    );
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsNothing);
    expect(find.byTooltip('Regenerate response'), findsNothing);
    expect(find.text('Original question'), findsOneWidget);
    expect(find.byType(AiAvatar), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered answer'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.byTooltip('Regenerate response'), findsOneWidget);
    expect(find.text('Original question'), findsOneWidget);
    expect(find.byType(AiAvatar), findsOneWidget);
    expect(attempts, 3);
    expect(tester.takeException(), isNull);
    await modelManager.dispose();
  });

  testWidgets('retrying an older error keeps Regenerate latest-only', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    var attempts = 0;
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() {
            attempts++;
            return switch (attempts) {
              1 => Stream<String>.error(Exception('generation failed')),
              2 => Stream.value('Newer answer'),
              _ => Stream.value('Recovered older answer'),
            };
          }),
          intentRouter: const _FixedChatIntentRouter(ChatRoute.chat),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'First question');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Second question');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Regenerate response'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered older answer'), findsOneWidget);
    expect(find.text('Newer answer'), findsOneWidget);
    expect(find.text('First question'), findsOneWidget);
    expect(find.text('Second question'), findsOneWidget);
    expect(find.byTooltip('Copy response'), findsNWidgets(2));
    expect(find.byTooltip('Regenerate response'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(attempts, 3);
    expect(tester.takeException(), isNull);
    await modelManager.dispose();
  });

  testWidgets('model load error hides technical details and can be retried', (
    tester,
  ) async {
    final repository = _RetryableModelRepository();
    final modelManager = LocalModelManager(repository);
    final askQuestion = _askQuestion(
      _FakeLlmService(() => Stream.value('Ready')),
    );
    Widget app(bool allowRetry) => MaterialApp(
      theme: ThemeData.dark(),
      home: AiChatPage(
        modelManager: modelManager,
        askQuestion: askQuestion,
        configuration: AiChatConfiguration(showRetryAction: allowRetry),
      ),
    );
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(modelManager.state.status, ModelStatus.error);
    expect(
      find.text('Local AI model could not be loaded. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('BackendInitException'), findsNothing);
    expect(find.text('Retry model loading'), findsNothing);
    await tester.pumpWidget(app(true));
    expect(find.text('Retry model loading'), findsOneWidget);
    await tester.tap(find.text('Retry model loading'));
    await tester.pump();
    expect(find.text('Retry model loading'), findsNothing);
    expect(find.text('Loading local AI model…'), findsOneWidget);
    expect(repository.loadCount, 2);
    repository.finishLoading.complete();
    await tester.pumpAndSettle();
    expect(modelManager.state.status, ModelStatus.ready);
    expect(find.text('Retry model loading'), findsNothing);
    expect(find.textContaining('could not be loaded'), findsNothing);
    expect(tester.takeException(), isNull);
    await modelManager.dispose();
  });

  testWidgets(
    'knowledge preparation failure stops loading without raw details',
    (tester) async {
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      await tester.pumpWidget(
        MyApp(
          modelManager: modelManager,
          askQuestion: _askQuestion(
            _FakeLlmService(() => Stream.value('unused')),
          ),
          prepareKnowledgeBase: () async {
            throw PlatformException(
              code: 'EmbeddingGemmaInitException',
              message: 'Internal stack trace',
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Local knowledge could not be prepared. Restart the app to try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('EmbeddingGemmaInitException'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Send message',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await modelManager.dispose();
    },
  );

  testWidgets(
    'unexpected knowledge preparation failure is recoverable on restart',
    (tester) async {
      final modelManager = LocalModelManager(_ReadyModelRepository());
      await modelManager.ensureReady();
      await tester.pumpWidget(
        MyApp(
          modelManager: modelManager,
          askQuestion: _askQuestion(
            _FakeLlmService(() => Stream.value('unused')),
          ),
          prepareKnowledgeBase: () async {
            throw Exception('Filesystem initialization details');
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Local knowledge could not be prepared. Restart the app to try again.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Filesystem initialization details'),
        findsNothing,
      );
      expect(find.textContaining('Preparing local knowledge'), findsNothing);
      expect(tester.takeException(), isNull);
      await modelManager.dispose();
    },
  );

  testWidgets('unsupported knowledge answer remains a normal response', (
    tester,
  ) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    const configuration = AiChatConfiguration();
    await tester.pumpWidget(
      MyApp(
        modelManager: modelManager,
        askQuestion: _askQuestion(
          _FakeLlmService(() => Stream.value('unused')),
          repository: _FakeRagRepository(const []),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'What is the capital of France?',
    );
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text(configuration.unsupportedQuestionMessage), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.byTooltip('Copy response'), findsOneWidget);
    expect(find.textContaining('Sources'), findsNothing);
    expect(tester.takeException(), isNull);
    await modelManager.dispose();
  });

  test('chat defaults are white-label and local-source aware', () {
    const configuration = AiChatConfiguration();
    const theme = AiChatTheme();

    expect(configuration.showLocalSources, isTrue);
    expect(configuration.sourceSectionLabel, 'Sources');
    expect(configuration.modelLabel, 'Qwen3 0.6B · Local');
    expect(configuration.showModelLabel, isTrue);
    expect(configuration.showRuntimeBackend, isTrue);
    expect(configuration.showGenerationTime, isTrue);
    expect(configuration.generationTimeLabel, 'Generated in');
    expect(configuration.scrollThreshold, 160);
    expect(configuration.assistantName, 'ViGuide AI');
    expect(configuration.assistantAvatar, isNull);
    expect(configuration.welcomeTitle, 'How can I help?');
    expect(configuration.welcomeMessage, isNotEmpty);
    expect(configuration.suggestions, hasLength(2));
    expect(configuration.showCopyAction, isTrue);
    expect(configuration.showRegenerateAction, isTrue);
    expect(configuration.showRetryAction, isTrue);
    expect(
      const AiChatConfiguration(showRetryAction: false).showRetryAction,
      isFalse,
    );
    expect(
      const AiChatConfiguration(
        showRegenerateAction: false,
      ).showRegenerateAction,
      isFalse,
    );
    expect(
      const AiChatConfiguration(showCopyAction: false).showCopyAction,
      isFalse,
    );
    expect(theme.avatarLabel, 'AI');
    expect(theme.primaryColor, const Color(0xFF3F51B5));
    expect(theme.assistantBubbleColor, const Color(0xFFF1F3F8));
    expect(theme.userBubbleColor, theme.primaryColor);
    expect(theme.userTextColor, Colors.white);
    expect(theme.assistantTextColor, const Color(0xFF1A1C20));
    expect(
      const AiChatTheme(primaryColor: Colors.yellow).userTextColor,
      const Color(0xFF1A1C20),
    );
    expect(
      const AiChatTheme(assistantBubbleColor: Colors.black).assistantTextColor,
      Colors.white,
    );
    expect(
      const AiChatTheme(userTextColor: Colors.blue).userTextColor,
      Colors.blue,
    );
    final dark = const AiChatTheme(
      primaryColor: Colors.amber,
      assistantBubbleColor: Colors.white,
    ).resolve(ThemeData.dark().colorScheme);
    expect(dark.backgroundColor, ThemeData.dark().colorScheme.surface);
    expect(dark.primaryColor, Colors.amber);
    expect(dark.userTextColor, const Color(0xFF1A1C20));
    expect(dark.assistantTextColor, const Color(0xFF1A1C20));
  });
}

class _MessagesController extends ChatController {
  _MessagesController({
    required super.modelManager,
    required super.askQuestion,
    required this.messages,
  });

  List<ChatMessage> messages;

  void setMessages(List<ChatMessage> value) {
    messages = value;
    notifyListeners();
  }

  @override
  ChatState get state => super.state.copyWith(messages: messages);
}

AskQuestionUseCase _askQuestion(
  _FakeLlmService llmService, {
  _FakeRagRepository? repository,
  ChatIntentRouter? intentRouter,
}) {
  return AskQuestionUseCase(
    ragRepository: repository ?? _FakeRagRepository(),
    llmService: llmService,
    intentRouter:
        intentRouter ?? const _FixedChatIntentRouter(ChatRoute.knowledge),
  );
}

class _FixedChatIntentRouter implements ChatIntentRouter {
  const _FixedChatIntentRouter(this.routeValue);

  final ChatRoute routeValue;

  @override
  Future<ChatRoute> route(String message) async => routeValue;
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
  _FakeRagRepository([
    this.results = const [
      RagSearchResult(
        document: KnowledgeDocument(
          id: 'network',
          title: 'Device network connection guide',
          content: 'Connect the device to the network.',
          metadata: {},
        ),
        similarity: 1,
      ),
    ],
  ]);

  List<RagSearchResult> results;
  var searchCount = 0;

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
    searchCount++;
    return results;
  }
}

class _RetryableRagRepository extends _FakeRagRepository {
  _RetryableRagRepository(this.secondSearch);

  final Future<void> secondSearch;
  int attempts = 0;

  @override
  Future<List<RagSearchResult>> search({
    required String query,
    int topK = 1,
    double threshold = 0,
  }) async {
    attempts++;
    if (attempts == 1) {
      throw StateError('EmbeddingGemma search failed');
    }
    await secondSearch;
    return super.search(query: query, topK: topK, threshold: threshold);
  }
}

class _CountingChatIntentRouter implements ChatIntentRouter {
  int calls = 0;

  @override
  Future<ChatRoute> route(String message) async {
    calls++;
    return ChatRoute.knowledge;
  }
}

class _RetryableModelRepository implements LocalModelRepository {
  final finishLoading = Completer<void>();
  int loadCount = 0;

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<void> download({required void Function(int progress) onProgress}) {
    throw UnsupportedError('Already installed');
  }

  @override
  Future<void> load() async {
    loadCount++;
    if (loadCount == 1) {
      throw StateError('BackendInitException: internal native details');
    }
    await finishLoading.future;
  }
}
