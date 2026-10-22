import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/ai_chat_configuration.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/widgets/chat_composer.dart';

void main() {
  testWidgets('suggestions scroll horizontally above the text field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? selected;
    final suggestions = [
      'Explain a fault with a very long question that wraps onto two lines.',
      'Need help with heating',
      'Check water pressure',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              controller: controller,
              enabled: true,
              onSend: () {},
              theme: const AiChatTheme(),
              modelLabel: null,
              runtimeBackend: null,
              suggestions: suggestions,
              onSuggestion: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Suggestions'), findsNothing);
    final panel = find.byKey(const ValueKey('chat-input-panel'));
    expect(
      find.descendant(of: panel, matching: find.byType(ActionChip)),
      findsNothing,
    );
    expect(
      tester.getBottomLeft(find.byType(ActionChip).first).dy,
      lessThan(tester.getTopLeft(panel).dy),
    );
    expect(
      tester.widget<ActionChip>(find.byType(ActionChip).first).shape,
      isA<StadiumBorder>(),
    );
    expect(tester.widget<Text>(find.text(suggestions.first)).maxLines, 1);
    expect(
      find.descendant(of: panel, matching: find.byType(TextField)),
      findsOneWidget,
    );
    final decoration =
        tester.widget<Container>(panel).decoration! as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.border,
      InputBorder.none,
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final focusedDecoration =
        tester.widget<Container>(panel).decoration! as BoxDecoration;
    expect(
      focusedDecoration.border,
      Border.all(color: const AiChatTheme().buttonColor, width: 2),
    );
    expect(
      tester.getBottomLeft(find.byType(ActionChip).first).dy,
      lessThan(tester.getTopLeft(find.byType(TextField)).dy),
    );
    final scrollView = find.byType(SingleChildScrollView);
    expect(
      tester.widget<SingleChildScrollView>(scrollView).scrollDirection,
      Axis.horizontal,
    );
    expect(tester.getSize(find.byType(ActionChip).first).width, lessThan(320));
    await tester.tap(find.byType(ActionChip).first);
    expect(selected, suggestions.first);
    await tester.drag(scrollView, const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text(suggestions.last));
    expect(selected, suggestions.last);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suggestions respect disabled state and empty configuration', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var taps = 0;
    Widget composer(List<String> suggestions) => MaterialApp(
      home: Scaffold(
        body: ChatComposer(
          controller: controller,
          enabled: false,
          onSend: () {},
          theme: const AiChatTheme(),
          modelLabel: null,
          runtimeBackend: null,
          suggestions: suggestions,
          onSuggestion: (_) => taps++,
        ),
      ),
    );
    await tester.pumpWidget(composer(['Need help']));
    expect(
      tester.widget<ActionChip>(find.byType(ActionChip)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Need help'));
    expect(taps, 0);
    await tester.pumpWidget(composer([]));
    expect(find.text('Suggestions'), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
