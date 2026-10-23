import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/ai_chat_configuration.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/widgets/ai_avatar.dart';

void main() {
  testWidgets('default assistant avatar loads the bundled Dumbledore image', (
    tester,
  ) async {
    const configuration = AiChatConfiguration();
    const theme = AiChatTheme();
    const image = AssetImage('assets/icons/dumbledore-48.png');
    expect(configuration.assistantAvatar, image);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiAvatar(
            theme: theme,
            assistantName: configuration.assistantName,
            assistantAvatar: configuration.assistantAvatar,
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(
        image,
        tester.element(find.byType(AiAvatar)),
        onError: (error, stack) => fail('Avatar asset failed to load: $error'),
      );
    });
    await tester.pumpAndSettle();
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
      image,
    );
    expect(find.byIcon(theme.avatarIcon), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the fallback icon when no avatar image is configured', (
    tester,
  ) async {
    const theme = AiChatTheme();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AiAvatar(theme: theme, assistantAvatar: null)),
      ),
    );

    expect(find.byIcon(theme.avatarIcon), findsOneWidget);
  });
}
