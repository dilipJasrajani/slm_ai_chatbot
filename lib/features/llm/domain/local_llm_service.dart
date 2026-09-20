/// Provides caller-facing text chunks from the active local language model.
abstract interface class LocalLlmService {
  Stream<String> generate(String prompt);

  Future<void> stop();

  Future<void> dispose();
}
