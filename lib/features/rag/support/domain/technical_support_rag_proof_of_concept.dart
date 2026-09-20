import '../../domain/ask_question_use_case.dart';
import '../../domain/ingest_documents_use_case.dart';

class TechnicalSupportRagProofOfConcept {
  TechnicalSupportRagProofOfConcept({
    required IngestDocumentsUseCase ingestDocuments,
    required AskQuestionUseCase askQuestion,
  }) : _ingestDocuments = ingestDocuments,
       _askQuestion = askQuestion;

  final IngestDocumentsUseCase _ingestDocuments;
  final AskQuestionUseCase _askQuestion;

  static const question = 'What is galaxy?';
  // 'My device cannot connect to Wi-Fi. What should I check?';

  Future<QuestionAnswer> run({
    void Function(DocumentIngestionProgress progress)? onProgress,
  }) async {
    await _ingestDocuments(onProgress: onProgress);
    return _askQuestion(question);
  }
}
