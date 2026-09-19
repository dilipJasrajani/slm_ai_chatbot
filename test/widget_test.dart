import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/domain/llm/local_llm_service.dart';
import 'package:slm_ai_chatbot/domain/model/local_model_manager.dart';
import 'package:slm_ai_chatbot/domain/model/local_model_repository.dart';
import 'package:slm_ai_chatbot/main.dart';

void main() {
  testWidgets('streams a local test response', (WidgetTester tester) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final llmService = _FakeLocalLlmService(
      response: Stream<String>.fromIterable(['Hello', ' from Gemma.']),
    );

    await tester.pumpWidget(
      MyApp(modelManager: modelManager, llmService: llmService),
    );
    await tester.tap(find.text('Generate Test Response'));
    await tester.pump();
    await tester.pump();

    expect(llmService.prompt, 'Hello! Introduce yourself in one sentence.');
    expect(find.text('Hello from Gemma.'), findsOneWidget);

    await modelManager.dispose();
  });

  testWidgets('shows local inference errors', (WidgetTester tester) async {
    final modelManager = LocalModelManager(_ReadyModelRepository());
    await modelManager.ensureReady();
    final llmService = _FakeLocalLlmService(
      response: Stream<String>.error(StateError('Local inference failed')),
    );

    await tester.pumpWidget(
      MyApp(modelManager: modelManager, llmService: llmService),
    );
    await tester.tap(find.text('Generate Test Response'));
    await tester.pump();

    expect(find.textContaining('Local inference failed'), findsOneWidget);

    await modelManager.dispose();
  });
}

class _ReadyModelRepository implements LocalModelRepository {
  @override
  Future<void> download({required void Function(int progress) onProgress}) {
    throw UnsupportedError('The test model is already installed.');
  }

  @override
  Future<bool> isInstalled() async => true;

  @override
  Future<void> load() async {}
}

class _FakeLocalLlmService implements LocalLlmService {
  _FakeLocalLlmService({required this.response});

  final Stream<String> response;
  String? prompt;

  @override
  Future<void> dispose() async {}

  @override
  Stream<String> generate(String prompt) {
    this.prompt = prompt;
    return response;
  }

  @override
  Future<void> stop() async {}
}
