import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_base_preparation.dart';

void main() {
  test('starts both model preparations before indexing documents', () async {
    final generationReady = Completer<void>();
    final embeddingReady = Completer<void>();
    var generationPreparations = 0;
    var embeddingPreparations = 0;
    var ingestionCalls = 0;
    final preparation = KnowledgeBasePreparation(
      ensureGenerationModelReady: () {
        generationPreparations++;
        return generationReady.future;
      },
      ensureEmbeddingModelReady: () {
        embeddingPreparations++;
        return embeddingReady.future;
      },
      ingestDocuments: () async {
        ingestionCalls++;
      },
    );

    preparation.startModelPreparation();

    expect(generationPreparations, 1);
    expect(embeddingPreparations, 1);
    expect(ingestionCalls, 0);

    final preparingKnowledge = preparation.prepareKnowledgeBase();
    generationReady.complete();
    await Future<void>.delayed(Duration.zero);
    expect(ingestionCalls, 0);

    embeddingReady.complete();
    await preparingKnowledge;
    expect(ingestionCalls, 1);
  });

  test('prepares the knowledge base only once', () async {
    var ingestionCalls = 0;
    final preparation = KnowledgeBasePreparation(
      ensureGenerationModelReady: () async {},
      ensureEmbeddingModelReady: () async {},
      ingestDocuments: () async {
        ingestionCalls++;
      },
    );

    await Future.wait([
      preparation.prepareKnowledgeBase(),
      preparation.prepareKnowledgeBase(),
    ]);

    expect(ingestionCalls, 1);
  });
}
