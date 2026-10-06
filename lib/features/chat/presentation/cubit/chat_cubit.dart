import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:slm_ai_chatbot/core/profiling/ai_latency_profile.dart';
import 'package:slm_ai_chatbot/features/chat/domain/ask_question_use_case.dart';
import 'package:slm_ai_chatbot/features/model/domain/local_model_manager.dart';
import 'package:slm_ai_chatbot/features/model/domain/model_status.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';
import '../models/chat_message.dart';
import 'chat_state.dart';

/// Converts chat UI events and use-case streams into immutable presentation state.
class ChatCubit extends Cubit<ChatState> {
  ChatCubit({
    required LocalModelManager modelManager,
    required AskQuestionUseCase askQuestion,
    Future<void> Function()? prepareKnowledgeBase,
  }) : _modelManager = modelManager,
       _askQuestion = askQuestion,
       _prepareKnowledgeBase = prepareKnowledgeBase,
       super(
         ChatState(
           modelState: modelManager.state,
           knowledgeReady: prepareKnowledgeBase == null,
         ),
       ) {
    _modelSubscription = _modelManager.states.listen(_onModelState);
    if (_modelManager.state.status == ModelStatus.ready) {
      _startKnowledgePreparation();
    } else {
      unawaited(_modelManager.ensureReady());
    }
  }

  final LocalModelManager _modelManager;
  final AskQuestionUseCase _askQuestion;
  final Future<void> Function()? _prepareKnowledgeBase;
  late final StreamSubscription<ModelState> _modelSubscription;
  var _messageSequence = 0;
  var _requestSequence = 0;
  final _pendingRenderedProfiles = <String, AiLatencyProfile>{};
  var _disposed = false;
  var _knowledgePreparationStarted = false;
  Future<void>? _closeFuture;

  void _startKnowledgePreparation() {
    if (_disposed ||
        _knowledgePreparationStarted ||
        _prepareKnowledgeBase == null) {
      return;
    }
    _knowledgePreparationStarted = true;
    _setState(state.copyWith(isPreparingKnowledge: true));
    unawaited(_prepareKnowledge());
  }

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
    } on StateError catch (error) {
      _knowledgePreparationFailed(error);
    } on FormatException catch (error) {
      _knowledgePreparationFailed(error);
    } on PlatformException catch (error) {
      _knowledgePreparationFailed(error);
    } on MissingPluginException catch (error) {
      _knowledgePreparationFailed(error);
    } on Exception catch (error) {
      // Local preparation adapters can surface package-specific exceptions.
      _knowledgePreparationFailed(error);
    }
  }

  void _knowledgePreparationFailed(Object error) {
    if (kDebugMode) {
      debugPrint('[Chat] Local knowledge preparation failed: $error');
    }
    _setState(
      state.copyWith(
        isPreparingKnowledge: false,
        knowledgeReady: false,
        knowledgeError:
            'Local knowledge could not be prepared. Restart the app to try again.',
      ),
    );
  }

  Future<ModelState> retryModelInitialization() {
    if (_disposed || state.modelState.status != ModelStatus.error) {
      throw StateError('The local model is not awaiting retry.');
    }
    return _modelManager.ensureReady();
  }

  Future<void> send(String value) async {
    final question = value.trim();
    if (_disposed || question.isEmpty || !state.canSend) return;
    await _runQuestion(question);
  }

  Future<String?> regenerate(ChatMessage message) {
    final index = state.messages.indexWhere((item) => item.id == message.id);
    final current = index < 0 ? null : state.messages[index];
    if (_disposed ||
        !state.canSend ||
        current == null ||
        current.author != ChatAuthor.assistant ||
        current.isStreaming ||
        current.isError ||
        current.text.isEmpty ||
        current.question == null ||
        current.question!.trim().isEmpty) {
      throw StateError('This assistant response cannot be regenerated.');
    }
    return _runQuestion(
      current.question!,
      previousAnswer: current,
      isLatestTurn: index == state.messages.length - 1,
    );
  }

  Future<String?> _runQuestion(
    String question, {
    ChatMessage? previousAnswer,
    ChatMessage? retryingAnswer,
    bool isLatestTurn = false,
  }) {
    final profile = kDebugMode
        ? AiLatencyProfile(requestNumber: ++_requestSequence)
        : null;
    return AiLatencyProfile.run(
      profile,
      () => _runQuestionWithProfile(
        question,
        previousAnswer: previousAnswer,
        retryingAnswer: retryingAnswer,
        isLatestTurn: isLatestTurn,
        profile: profile,
      ),
    );
  }

  Future<String?> _runQuestionWithProfile(
    String question, {
    required AiLatencyProfile? profile,
    ChatMessage? previousAnswer,
    ChatMessage? retryingAnswer,
    bool isLatestTurn = false,
  }) async {
    final assistantId = (previousAnswer ?? retryingAnswer)?.id ?? _nextId();
    if (profile != null) _pendingRenderedProfiles[assistantId] = profile;
    final streamingAnswer = ChatMessage(
      id: assistantId,
      author: ChatAuthor.assistant,
      text: '',
      isStreaming: true,
      question: question,
    );
    if (previousAnswer == null && retryingAnswer == null) {
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
            streamingAnswer,
          ],
        ),
      );
    } else {
      _setState(
        state.copyWith(
          isTyping: true,
          messages: [
            for (final message in state.messages)
              if (message.id == assistantId) streamingAnswer else message,
          ],
        ),
      );
    }
    QuestionAnswer? lastAnswer;
    Duration? generationDuration;
    String? regenerationError;
    var completed = false;
    try {
      await for (final answer in _askQuestion.stream(
        question,
        onGenerationComplete: (duration) => generationDuration = duration,
        turnId: assistantId,
        regenerate: previousAnswer != null,
        isLatestTurn: isLatestTurn,
      )) {
        if (_disposed) return null;
        lastAnswer = answer;
        final isError =
            answer.status == QuestionAnswerStatus.retrievalFailure ||
            answer.status == QuestionAnswerStatus.modelUnavailable ||
            answer.status == QuestionAnswerStatus.generationFailure;
        if (isError && previousAnswer != null) {
          regenerationError = answer.answer;
          continue;
        }
        _replaceMessage(
          assistantId,
          text: answer.answer,
          isStreaming: true,
          isError: isError,
        );
        if (answer.answer.trim().isNotEmpty) {
          profile?.mark(AiProfileEvent.firstPresentationText);
        }
      }
      completed = true;
    } finally {
      if (!_disposed) {
        if (previousAnswer != null &&
            (!completed || regenerationError != null)) {
          _setState(
            state.copyWith(
              messages: [
                for (final message in state.messages)
                  if (message.id == assistantId) previousAnswer else message,
              ],
            ),
          );
        } else {
          _replaceMessage(
            assistantId,
            isStreaming: false,
            sources:
                completed && lastAnswer?.status == QuestionAnswerStatus.answered
                ? lastAnswer!.documents
                : const [],
            generationDuration:
                completed && lastAnswer?.status == QuestionAnswerStatus.answered
                ? generationDuration
                : null,
          );
        }
        _setState(state.copyWith(isTyping: false));
      }
      profile?.complete(
        _disposed ? 'cancelled' : lastAnswer?.status.name ?? 'interrupted',
      );
    }
    return regenerationError;
  }

  Future<void> retry(ChatMessage message) {
    final index = state.messages.indexWhere((item) => item.id == message.id);
    final current = index < 0 ? null : state.messages[index];
    if (_disposed ||
        !state.canSend ||
        current == null ||
        current.author != ChatAuthor.assistant ||
        !current.isError ||
        current.isStreaming ||
        current.text.isEmpty ||
        current.question == null ||
        current.question!.trim().isEmpty) {
      throw StateError('This assistant response cannot be retried.');
    }
    return _runQuestion(current.question!, retryingAnswer: current);
  }

  void clearHistory() {
    if (_disposed || state.isTyping) return;
    _askQuestion.clearHistory();
    _pendingRenderedProfiles.clear();
    _setState(state.copyWith(messages: const []));
  }

  bool isFirstRenderedTextPending(String messageId) =>
      _pendingRenderedProfiles[messageId]?.isFirstRenderedTextPending ?? false;

  int? pendingRenderedRequestNumber(String messageId) {
    final profile = _pendingRenderedProfiles[messageId];
    return profile?.isFirstRenderedTextPending ?? false
        ? profile!.requestNumber
        : null;
  }

  void recordFirstRenderedText(String messageId, {int? requestNumber}) {
    final profile = _pendingRenderedProfiles[messageId];
    if (requestNumber != null && profile?.requestNumber != requestNumber) {
      return;
    }
    _pendingRenderedProfiles.remove(messageId)?.recordFirstRenderedText();
  }

  void _onModelState(ModelState modelState) {
    _setState(state.copyWith(modelState: modelState));
    if (modelState.status == ModelStatus.ready) {
      _startKnowledgePreparation();
    }
  }

  void _replaceMessage(
    String id, {
    String? text,
    bool? isStreaming,
    bool? isError,
    List<KnowledgeDocument>? sources,
    Duration? generationDuration,
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
                      sources: sources,
                      generationDuration: generationDuration,
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
    emit(nextState);
  }

  @override
  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    // Guard synchronously: page disposal cannot await asynchronous cleanup.
    _disposed = true;
    _pendingRenderedProfiles.clear();
    return _closeFuture = Future.wait([
      _modelSubscription.cancel(),
      _askQuestion.cancel(),
      super.close(),
    ]).then((_) {});
  }
}
