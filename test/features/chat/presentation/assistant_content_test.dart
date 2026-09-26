import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/ai_chat_configuration.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/assistant_content.dart';

void main() {
  Widget content(String answer, {ThemeData? hostTheme}) {
    final theme = hostTheme ?? ThemeData.light();
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AssistantContent(
              text: answer,
              theme: const AiChatTheme().resolve(theme.colorScheme),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('plain text stays readable and paragraphs are separated', (
    tester,
  ) async {
    await tester.pumpWidget(content('A plain answer.'));
    expect(find.text('A plain answer.'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('A plain answer.')).style?.height,
      1.4,
    );

    await tester.pumpWidget(content('First paragraph.\n\nSecond paragraph.'));
    expect(find.text('First paragraph.'), findsOneWidget);
    expect(find.text('Second paragraph.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Second paragraph.')).dy,
      greaterThan(tester.getBottomLeft(find.text('First paragraph.')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('headings, bullets, numbered steps and inline code render', (
    tester,
  ) async {
    await tester.pumpWidget(
      content(
        '## Possible Causes\n\n'
        '- One\n- Two\n- Three\n\n'
        '1. Check the network\n2. Retry\n\n'
        'Use `E123` to retry.',
      ),
    );
    expect(find.text('Possible Causes'), findsOneWidget);
    expect(find.text('## Possible Causes'), findsNothing);
    final heading = tester.widget<Text>(find.text('Possible Causes'));
    final bodySize = Theme.of(
      tester.element(find.byType(AssistantContent)),
    ).textTheme.bodyMedium!.fontSize!;
    expect(
      _textSpans(
        heading.textSpan!,
      ).any((span) => (span.style?.fontSize ?? 0) > bodySize),
      isTrue,
    );
    for (final item in ['One', 'Two', 'Three']) {
      expect(find.text(item), findsOneWidget);
      expect(find.text('- $item'), findsNothing);
    }
    expect(find.text('•'), findsNWidgets(3));
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('Check the network'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    final inlineText = tester.widget<Text>(find.text('Use E123 to retry.'));
    expect(
      _textSpans(inlineText.textSpan!).any(
        (span) => span.text == 'E123' && span.style?.fontFamily == 'monospace',
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('code blocks preserve lines and copy only the raw code', (
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
    const code = 'final value = 10;\n  print(value);';
    await tester.pumpWidget(
      content('Here is the code:\n\n```dart\n$code\n```'),
    );
    expect(find.text('Here is the code:'), findsOneWidget);
    expect(find.text('dart'), findsOneWidget);
    expect(find.text(code), findsOneWidget);
    expect(tester.widget<Text>(find.text(code)).style?.fontFamily, 'monospace');
    expect(find.textContaining('```'), findsNothing);
    expect(find.byTooltip('Copy code'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy code'));
    await tester.pump();
    expect(clipboardText, code);
    expect(find.byTooltip('Code copied'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each code block copies independently in mixed content', (
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
    const answer =
        '## Troubleshooting\n\nCheck the device.\n\n'
        '- Connect the cable\n- Check `E123`\n\n'
        '```json\n{"ready": true}\n```\n\n'
        'Then run:\n\n```bash\n  echo ready\n```\n\nTry again.';
    await tester.pumpWidget(content(answer));
    expect(find.text('Troubleshooting'), findsOneWidget);
    expect(find.text('Check the device.'), findsOneWidget);
    expect(find.text('Connect the cable'), findsOneWidget);
    expect(find.text('{"ready": true}'), findsOneWidget);
    expect(find.text('  echo ready'), findsOneWidget);
    expect(find.text('Try again.'), findsOneWidget);
    expect(find.byTooltip('Copy code'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Copy code').first);
    await tester.pump();
    expect(clipboardText, '{"ready": true}');
    await tester.tap(find.byTooltip('Copy code').last);
    await tester.pump();
    expect(clipboardText, '  echo ready');
    expect(tester.takeException(), isNull);
  });

  testWidgets('common fenced language labels render without highlighting', (
    tester,
  ) async {
    for (final language in [
      'dart',
      'flutter',
      'json',
      'bash',
      'shell',
      'kotlin',
      'swift',
      'java',
      'javascript',
      'typescript',
    ]) {
      await tester.pumpWidget(content('```$language\n  sample\n```'));
      expect(find.text(language), findsOneWidget);
      expect(find.text('  sample'), findsOneWidget);
      expect(find.byTooltip('Copy code'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('code scrolls inside narrow and wide light/dark layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final longLine = 'final value = "${'x' * 220}";';
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      for (final size in [
        const Size(280, 640),
        const Size(400, 860),
        const Size(900, 1100),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          content(
            '## Guide\n\n`E123`\n\n```kotlin\n$longLine\n```',
            hostTheme: theme,
          ),
        );
        expect(find.text('Guide'), findsOneWidget);
        expect(find.text(longLine), findsOneWidget);
        expect(find.byTooltip('Copy code'), findsOneWidget);
        final scroll = find.ancestor(
          of: find.text(longLine),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SingleChildScrollView &&
                widget.scrollDirection == Axis.horizontal,
          ),
        );
        expect(scroll, findsOneWidget);
        expect(tester.getSize(scroll).width, lessThan(size.width));
        expect(
          tester.widget<Text>(find.text(longLine)).style?.color,
          const AiChatTheme().resolve(theme.colorScheme).surfaceTextColor,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('remote Markdown images show alt text without loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      content('See ![Wiring diagram](https://example.invalid/diagram.png).'),
    );
    expect(find.textContaining('Wiring diagram'), findsWidgets);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Iterable<TextSpan> _textSpans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? <InlineSpan>[]) {
      yield* _textSpans(child);
    }
  }
}
