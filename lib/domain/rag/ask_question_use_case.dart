import '../llm/local_llm_service.dart';
import 'document_context_builder.dart';
import 'knowledge_document.dart';
import 'rag_prompt_builder.dart';
import 'rag_repository.dart';

enum QuestionAnswerStatus {
  answered,
  noRelevantKnowledge,
  retrievalFailure,
  modelUnavailable,
  generationFailure,
}

class QuestionAnswer {
  const QuestionAnswer({
    required this.status,
    required this.answer,
    this.documents = const [],
  });

  final QuestionAnswerStatus status;
  final String answer;
  final List<KnowledgeDocument> documents;
}

class AskQuestionUseCase {
  AskQuestionUseCase({
    required RagRepository ragRepository,
    required LocalLlmService llmService,
    DocumentContextBuilder contextBuilder = const DocumentContextBuilder(),
    RagPromptBuilder promptBuilder = const RagPromptBuilder(),
  }) : _ragRepository = ragRepository,
       _llmService = llmService,
       _contextBuilder = contextBuilder,
       _promptBuilder = promptBuilder;

  static const noRelevantKnowledgeAnswer =
      "I couldn't find relevant information in the local knowledge base.";

  final RagRepository _ragRepository;
  final LocalLlmService _llmService;
  final DocumentContextBuilder _contextBuilder;
  final RagPromptBuilder _promptBuilder;

  Future<QuestionAnswer> call(String question) async {
    final documents = await _retrieveDocuments(question);
    if (documents == null) {
      return const QuestionAnswer(
        status: QuestionAnswerStatus.retrievalFailure,
        answer: 'Unable to search the local knowledge base.',
      );
    }
    if (documents.isEmpty) {
      return const QuestionAnswer(
        status: QuestionAnswerStatus.noRelevantKnowledge,
        answer: noRelevantKnowledgeAnswer,
      );
    }

    final prompt = _promptBuilder.build(
      question: question,
      context: _contextBuilder.build(documents),
    );
    try {
      final response = StringBuffer();
      await for (final chunk in _llmService.generate(prompt)) {
        response.write(chunk);
      }
      final answer = response.toString().trim();
      if (answer.isEmpty) {
        return QuestionAnswer(
          status: QuestionAnswerStatus.generationFailure,
          answer: 'The local AI model did not generate an answer.',
          documents: documents,
        );
      }
      return QuestionAnswer(
        status: QuestionAnswerStatus.answered,
        answer: answer,
        documents: documents,
      );
    } on StateError {
      return QuestionAnswer(
        status: QuestionAnswerStatus.modelUnavailable,
        answer: 'Local AI model is not installed or could not be loaded.',
        documents: documents,
      );
    } catch (_) {
      return QuestionAnswer(
        status: QuestionAnswerStatus.generationFailure,
        answer: 'Unable to generate an answer with the local AI model.',
        documents: documents,
      );
    }
  }

  Future<List<KnowledgeDocument>?> _retrieveDocuments(String question) async {
    try {
      final results = await _ragRepository.search(query: question, topK: 3);
      return results.map((result) => result.document).toList(growable: false);
    } catch (_) {
      return null;
    }
  }
}
