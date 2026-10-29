import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/core/profiling/ai_latency_profile.dart';
import 'package:slm_ai_chatbot/features/chat/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_history.dart';
import 'package:slm_ai_chatbot/features/chat/domain/conversation_message.dart';
import 'package:slm_ai_chatbot/features/llm/domain/local_llm_service.dart';
import 'package:slm_ai_chatbot/features/rag/data/json_document_source.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_document.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_repository.dart';
import 'package:slm_ai_chatbot/features/rag/domain/rag_search_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const clock = KnowledgeDocument(
    id: 'card:msg:f_425',
    title: 'FAULT F.425',
    content:
        'Cause: Time synchronisation not possible.\n'
        'Measures: Replace CR2032 battery in HPMU electronics module.',
    metadata: {'code': 'F.425'},
  );
  const vent = KnowledgeDocument(
    id: 'card:msg:f_867',
    title: 'FAULT F.867',
    content:
        'Cause: Float air vent valve in the outdoor unit has responded.\n'
        'Heat pump switches off during venting.\n'
        'Danger: Escaping refrigerant can lead to explosions.\n'
        'During operation: Isolate the system from the power supply.',
    metadata: {'code': 'F.867'},
  );

  for (final (first, second) in [(clock, vent), (vent, clock)]) {
    test(
      '${first.id} followed by ${second.id} isolates evidence from history',
      () async {
        final rag = _Rag([clock, vent]);
        final llm = _Llm();
        final useCase = AskQuestionUseCase(ragRepository: rag, llmService: llm);
        await useCase('What does error ${first.metadata['code']} mean?');
        const earlierAnswer = 'Earlier generated answer (not evidence)';
        llm.answer = earlierAnswer;
        await useCase('What does error ${first.metadata['code']} mean?');
        final question = 'What does error ${second.metadata['code']} mean?';
        final profile = AiLatencyProfile(requestNumber: 1, log: (_) {});
        final result = await AiLatencyProfile.run(
          profile,
          () => useCase(question),
        );

        expect(rag.query, question);
        expect(rag.exactMatchQuery, question);
        expect(result.documents.map((doc) => doc.id), [second.id]);
        expect(llm.prompt, contains(second.content));
        expect(llm.prompt, isNot(contains(first.content)));
        final knowledge = llm.prompt!
            .split('<knowledge>\n')
            .last
            .split('</knowledge>')
            .first;
        expect(knowledge, isNot(contains(first.metadata['code'])));
        expect(knowledge, isNot(contains(earlierAnswer)));
        expect(llm.prompt, contains(earlierAnswer));
        expect(llm.prompt, contains('<conversation_history>'));
        expect(llm.prompt, contains('ignore unrelated history'));
        expect(profile.historyMessageCount, 4);
        expect(profile.historyCharacters, greaterThan(0));
      },
    );
  }

  test(
    'follow-up resolves the latest fault for exact lookup and prompt',
    () async {
      final rag = _Rag([clock, vent]);
      final llm = _Llm();
      final useCase = AskQuestionUseCase(ragRepository: rag, llmService: llm);
      await useCase('What does error F.867 mean?');
      final result = await useCase('How do I fix it?');
      expect(rag.query, 'How do I fix fault F867?');
      expect(rag.exactMatchQuery, rag.query);
      expect(result.documents.map((doc) => doc.id), [vent.id]);
      expect(llm.prompt, contains('How do I fix fault F867?'));
      expect(llm.prompt, isNot(contains(clock.content)));
    },
  );

  test(
    'ambiguous comparison follow-up asks instead of searching or generating',
    () async {
      final history = InMemoryConversationHistory()
        ..addAll(const [
          ConversationMessage(
            author: ConversationAuthor.user,
            text: 'Compare F.425 and F.867.',
          ),
          ConversationMessage(
            author: ConversationAuthor.assistant,
            text: 'Both records were explained.',
          ),
        ]);
      final rag = _Rag([clock, vent]);
      final llm = _Llm();
      final result = await AskQuestionUseCase(
        ragRepository: rag,
        llmService: llm,
        conversationHistory: history,
      )('How do I fix it?');
      expect(result.status, QuestionAnswerStatus.noRelevantKnowledge);
      expect(result.answer, contains('Which fault code'));
      expect(rag.calls, 0);
      expect(llm.calls, 0);
      expect(history.messages, hasLength(4));
    },
  );

  test(
    'comparison retains both identities in separate knowledge records',
    () async {
      final llm = _Llm();
      final result = await AskQuestionUseCase(
        ragRepository: _Rag([clock, vent]),
        llmService: llm,
      )('Compare F.425 and F.867.');
      expect(result.documents.map((doc) => doc.id), [clock.id, vent.id]);
      expect(llm.prompt, contains('<target_fault_codes>\nF425, F867'));
      expect(llm.prompt, contains('separate labelled section'));
      expect(llm.prompt, contains('Never combine causes, symptoms, or repair'));
      expect(llm.prompt, contains('Knowledge Document 1'));
      expect(llm.prompt, contains('Knowledge Document 2'));
      expect(llm.prompt, contains(clock.content));
      expect(llm.prompt, contains(vent.content));
    },
  );

  test(
    'unknown code never substitutes similar faults or calls the model',
    () async {
      final llm = _Llm();
      final result = await AskQuestionUseCase(
        ragRepository: _Rag([clock, vent]),
        llmService: llm,
      )('What does error F.999 mean?');
      expect(result.status, QuestionAnswerStatus.noRelevantKnowledge);
      expect(result.answer, contains('no matching record for F999'));
      expect(result.documents, isEmpty);
      expect(llm.calls, 0);
    },
  );

  test(
    'partially missing comparison does not generate a misleading comparison',
    () async {
      final llm = _Llm();
      final result = await AskQuestionUseCase(
        ragRepository: _Rag([clock, vent]),
        llmService: llm,
      )('Compare F.425 and F.999.');
      expect(result.status, QuestionAnswerStatus.noRelevantKnowledge);
      expect(result.answer, contains('F999'));
      expect(llm.calls, 0);
    },
  );

  test('an unknown fault remains the subject of the next follow-up', () async {
    final rag = _Rag([clock, vent]);
    final llm = _Llm();
    final useCase = AskQuestionUseCase(ragRepository: rag, llmService: llm);
    await useCase('What does F.425 mean?');
    await useCase('What does F.999 mean?');
    final callsBeforeFollowUp = llm.calls;
    final result = await useCase('How do I fix it?');
    expect(rag.exactMatchQuery, 'How do I fix fault F999?');
    expect(result.status, QuestionAnswerStatus.noRelevantKnowledge);
    expect(result.documents, isEmpty);
    expect(llm.calls, callsBeforeFollowUp);
  });

  test(
    'ordinary no-code follow-up is resolved once throughout the pipeline',
    () async {
      final rag = _Rag([vent]);
      final llm = _Llm();
      final useCase = AskQuestionUseCase(ragRepository: rag, llmService: llm);
      await useCase('Why does the heat pump switch off during venting?');
      final result = await useCase('Tell me more.');
      expect(result.status, QuestionAnswerStatus.answered);
      expect(
        rag.query,
        'Tell me more.\n'
        'Subject: Why does the heat pump switch off during venting?',
      );
      expect(llm.prompt, contains(rag.query!));
      expect(llm.prompt, contains(llm.answer));
      expect(llm.prompt, contains('<current_user_question>\nTell me more.'));
      expect(llm.prompt, contains('History is conversational context only'));
      expect(result.documents.single.id, vent.id);
    },
  );

  test(
    'no-code semantic question retains ranking, topK and threshold',
    () async {
      final rag = _Rag([vent, clock]);
      final llm = _Llm();
      final result = await AskQuestionUseCase(
        ragRepository: rag,
        llmService: llm,
      )('What should I check if the heat pump switches off during venting?');
      expect(result.documents.map((doc) => doc.id), [vent.id]);
      expect(rag.topK, 3);
      expect(rag.threshold, 0);
      expect(llm.calls, 1);
    },
  );

  test(
    'real asset keeps fault warnings and conditional procedures intact',
    () async {
      final documents = await JsonDocumentSource(
        assetBundle: rootBundle,
        assetPath: 'assets/knowledge_base/kb_mobile_v1_1.json',
      ).loadDocuments();
      final llm = _Llm();
      final result = await AskQuestionUseCase(
        ragRepository: _Rag(documents),
        llmService: llm,
      )('What does error F.867 mean?');
      expect(result.documents, isNotEmpty);
      expect(
        result.documents.every(
          (doc) =>
              doc.metadata['code'] == 'F.867' || doc.title.startsWith('F.867'),
        ),
        isTrue,
      );
      for (final phrase in [
        'specific qualifications and certification',
        'Danger Escaping refrigerant can lead to explosions',
        'If a message appears during venting:',
        'If a message appears during operation:',
        'Notify Viessmann Werke Technical Service.',
      ]) {
        expect(llm.prompt, contains(phrase));
      }
      expect(llm.prompt, isNot(contains('CR2032')));
    },
  );
}

class _Rag implements RagRepository {
  _Rag(this.documents);
  final List<KnowledgeDocument> documents;
  String? query;
  String? exactMatchQuery;
  int calls = 0;
  int? topK;
  double? threshold;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> indexDocuments(Iterable<RagDocument> documents) async {}

  @override
  Future<List<RagSearchResult>> search({
    required String query,
    String? exactMatchQuery,
    int topK = 1,
    double threshold = 0,
  }) async {
    calls++;
    this.query = query;
    this.exactMatchQuery = exactMatchQuery;
    this.topK = topK;
    this.threshold = threshold;
    // Deliberately return unrelated hits with high scores to test enforcement.
    return [
      for (final document in documents)
        RagSearchResult(document: document, similarity: 0.99),
    ];
  }
}

class _Llm implements LocalLlmService {
  String? prompt;
  String answer = 'Deterministic generated explanation.';
  int calls = 0;

  @override
  Stream<String> generate(String prompt) {
    this.prompt = prompt;
    calls++;
    return Stream.value(answer);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
