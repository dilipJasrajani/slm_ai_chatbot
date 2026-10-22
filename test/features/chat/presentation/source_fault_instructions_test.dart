import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/ai_chat_configuration.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/models/chat_message.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/widgets/chat_message_bubble.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';

void main() {
  for (final isError in [false, true]) {
    testWidgets(
      'source instructions expand and collapse with sources disabled, '
      'generation error=$isError',
      (tester) async {
        const warning =
            'Danger: Escaping refrigerant can lead to explosions.\n'
            'If a message appears during operation:\n'
            'Isolate the system from the power supply.';
        const measures = 'Only qualified and certified personnel may proceed.';
        final source = KnowledgeDocument(
          id: 'fault-guide',
          title: 'FAULT F.867',
          content: jsonEncode({'text': warning}),
          measures: measures,
          metadata: const {'code': 'F.867'},
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ChatMessageBubble(
                  message: ChatMessage(
                    id: 'answer',
                    author: ChatAuthor.assistant,
                    text: isError
                        ? 'Generation failed.'
                        : 'Generated explanation.',
                    isError: isError,
                    sources: [source],
                  ),
                  theme: const AiChatTheme(assistantTextColor: Colors.green),
                  showSources: false,
                  showGenerationTime: false,
                  showCopyAction: false,
                  showRegenerateAction: false,
                  showRetryAction: false,
                  retryEnabled: false,
                  regenerateEnabled: false,
                  generationTimeLabel: 'Time',
                  assistantName: 'Assistant',
                  assistantAvatar: null,
                  sourceSectionLabel: 'Sources',
                  seenMessages: {'answer'},
                  onRetry: () {},
                  onRegenerate: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('View sources'), findsOneWidget);
        expect(find.text('ViSage explanation'), findsOneWidget);
        expect(find.byType(SelectableText), findsNothing);
        final toggle = find.widgetWithText(TextButton, 'View sources');
        final buttonRect = tester.getRect(toggle);
        final sectionRect = tester.getRect(find.byType(ChatMessageBubble));
        expect(buttonRect.width, lessThan(sectionRect.width / 2));
        await tester.tapAt(Offset(sectionRect.right - 8, buttonRect.center.dy));
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsNothing);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        final text = tester.widget<SelectableText>(find.byType(SelectableText));
        expect(text.data, contains(warning));
        expect(text.data, contains(measures));
        expect(text.style?.color, Colors.green);
        expect(
          tester.getTopLeft(find.byType(SelectableText)).dy,
          lessThan(tester.getTopLeft(find.text('ViSage explanation')).dy),
        );
        await tester.tapAt(tester.getRect(find.byType(SelectableText)).center);
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsOneWidget);
        await tester.ensureVisible(find.text('Hide sources'));
        await tester.tap(find.text('Hide sources'));
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsNothing);
        expect(find.text('ViSage explanation'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
