import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:slm_ai_chatbot/features/chat/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_manager.dart';
import 'package:slm_ai_chatbot/features/model/domain/model_status.dart';
import 'chat_models.dart';

class ChatController extends ChangeNotifier {
  ChatController({
    required LocalModelManager modelManager,
    required AskQuestionUseCase askQuestion,
    Future<void> Function()? prepareKnowledgeBase,
  }) : _modelManager = modelManager,
       _askQuestion = askQuestion,
       _prepareKnowledgeBase = prepareKnowledgeBase,
       _state = ChatState(
         modelState: modelManager.state,
         isPreparingKnowledge: prepareKnowledgeBase != null,
         knowledgeReady: prepareKnowledgeBase == null,
       ) {
    _modelSubscription = _modelManager.states.listen(_onModelState);
    unawaited(_modelManager.ensureReady());
    if (_prepareKnowledgeBase != null) {
      unawaited(_prepareKnowledge());
    }
  }

  final LocalModelManager _modelManager;
  final AskQuestionUseCase _askQuestion;
  final Future<void> Function()? _prepareKnowledgeBase;
  late final StreamSubscription<ModelState> _modelSubscription;
  ChatState _state;
  var _messageSequence = 0;
  var _disposed = false;

  ChatState get state => _state;

  Future<void> _prepareKnowledge() async {
    try {
      await _prepareKnowledgeBase!();
      _setState(
        state.copyWith(
          isPreparingKnowledge: false,
          knowledgeReady: true,
          clearKnowledgeError: true,
        ),
      );
    } on StateError {
      _setState(
        state.copyWith(
          isPreparingKnowledge: false,
          knowledgeReady: false,
          knowledgeError: 'Local knowledge could not be prepared.',
        ),
      );
    } on FormatException {
      _setState(
        state.copyWith(
          isPreparingKnowledge: false,
          knowledgeReady: false,
          knowledgeError: 'Local knowledge could not be prepared.',
        ),
      );
    }
  }

  Future<void> send(String value) async {
    final question = value.trim();
    if (question.isEmpty || !state.canSend) return;

    final assistantId = _nextId();
    _setState(
      state.copyWith(
        isTyping: true,
        messages: [
          ...state.messages,
          ChatMessage(
            id: _nextId(),
            author: ChatAuthor.user,
            text: question,
            question: question,
          ),
          ChatMessage(
            id: assistantId,
            author: ChatAuthor.assistant,
            text: '',
            isStreaming: true,
            question: question,
          ),
        ],
      ),
    );

    try {
      await for (final answer in _askQuestion.stream(question)) {
        if (_disposed) return;
        final isError =
            answer.status == QuestionAnswerStatus.retrievalFailure ||
            answer.status == QuestionAnswerStatus.modelUnavailable ||
            answer.status == QuestionAnswerStatus.generationFailure;
        if (isError) {
          _setState(state.copyWith(isTyping: false));
        }
        _replaceMessage(
          assistantId,
          text: answer.answer,
          isStreaming: true,
          isError: isError,
          sourceTitles: answer.documents
              .map((document) => document.title)
              .toList(growable: false),
        );
      }
    } finally {
      if (!_disposed) {
        _replaceMessage(assistantId, isStreaming: false);
        _setState(state.copyWith(isTyping: false));
      }
    }
  }

  Future<void> retry(ChatMessage message) {
    final question = message.question;
    return question == null ? Future<void>.value() : send(question);
  }

  void clearHistory() {
    if (state.isTyping) return;
    _askQuestion.clearHistory();
    _setState(state.copyWith(messages: const []));
  }

  void _onModelState(ModelState modelState) {
    _setState(state.copyWith(modelState: modelState));
  }

  void _replaceMessage(
    String id, {
    String? text,
    bool? isStreaming,
    bool? isError,
    List<String>? sourceTitles,
  }) {
    _setState(
      state.copyWith(
        messages: state.messages
            .map(
              (message) => message.id == id
                  ? message.copyWith(
                      text: text,
                      isStreaming: isStreaming,
                      isError: isError,
                      sourceTitles: sourceTitles,
                    )
                  : message,
            )
            .toList(growable: false),
      ),
    );
  }

  String _nextId() => 'message-${_messageSequence++}';

  void _setState(ChatState nextState) {
    if (_disposed) return;
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_modelSubscription.cancel());
    unawaited(_askQuestion.cancel());
    super.dispose();
  }
}
