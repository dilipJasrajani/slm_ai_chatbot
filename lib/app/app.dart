import 'package:flutter/material.dart';

import 'package:slm_ai_chatbot/features/chat/evaluation/domain/chat_intent_evaluation_runner.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/ai_chat_page.dart';
import 'package:slm_ai_chatbot/features/chat/presentation/ai_chat_configuration.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_manager.dart';
import 'package:slm_ai_chatbot/features/chat/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/rag/evaluation/domain/retrieval_evaluation_runner.dart';

/// Application shell that configures the root chat experience.
class MyApp extends StatelessWidget {
  const MyApp({
    required this.modelManager,
    required this.askQuestion,
    this.chatIntentEvaluationRunner,
    this.retrievalEvaluationRunner,
    this.prepareKnowledgeBase,
    this.chatConfiguration = const AiChatConfiguration(),
    super.key,
  });

  final LocalModelManager modelManager;
  final AskQuestionUseCase askQuestion;
  final ChatIntentEvaluationRunner? chatIntentEvaluationRunner;
  final RetrievalEvaluationRunner? retrievalEvaluationRunner;
  final Future<void> Function()? prepareKnowledgeBase;
  final AiChatConfiguration chatConfiguration;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Assistant',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: AiChatPage(
        modelManager: modelManager,
        askQuestion: askQuestion,
        configuration: chatConfiguration,
        chatIntentEvaluationRunner: chatIntentEvaluationRunner,
        prepareKnowledgeBase: prepareKnowledgeBase,
        retrievalEvaluationRunner: retrievalEvaluationRunner,
      ),
    );
  }
}
