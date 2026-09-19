class RagPromptBuilder {
  const RagPromptBuilder();

  String build({required String question, required String context}) {
    return '''You are a technical knowledge assistant.

Answer the user's question using the provided knowledge.

Rules:
- Use the provided knowledge as the primary source.
- Do not invent facts that are not supported by the provided knowledge.
- If the knowledge does not contain enough information to answer, say that the information is not available in the knowledge base.
- Keep the answer concise and useful.

Knowledge:
$context

User question:
$question

Answer:''';
  }
}
