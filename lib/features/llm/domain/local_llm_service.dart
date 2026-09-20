abstract interface class LocalLlmService {
  Stream<String> generate(String prompt);

  Future<void> stop();

  Future<void> dispose();
}
