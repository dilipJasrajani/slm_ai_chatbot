import 'dart:io';

import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists vectors and retrieves the closest document', () async {
    final path =
        '${Directory.systemTemp.path}/slm_ai_chatbot_rag_${DateTime.now().microsecondsSinceEpoch}.db';
    final store = SqliteVectorStore();

    try {
      await store.initialize(path);
      await store.addDocument(
        id: 'error-e123',
        content: 'The device failed to establish a network connection.',
        embedding: [1.0, 0.0, 0.0],
      );
      await store.addDocument(
        id: 'error-e456',
        content: 'The temperature sensor is not responding.',
        embedding: [0.0, 1.0, 0.0],
      );
      await store.addDocument(
        id: 'error-e789',
        content: 'The firmware update package is corrupted.',
        embedding: [0.0, 0.0, 1.0],
      );
      await store.close();

      final reopenedStore = SqliteVectorStore();
      await reopenedStore.initialize(path);
      final results = await reopenedStore.searchSimilar(
        queryEmbedding: [1.0, 0.0, 0.0],
        topK: 1,
      );

      expect(results, hasLength(1));
      expect(results.single.id, 'error-e123');
      expect(results.single.similarity, closeTo(1.0, 0.0001));

      await reopenedStore.close();
    } finally {
      await store.close();
      final databaseFile = File(path);
      if (databaseFile.existsSync()) {
        databaseFile.deleteSync();
      }
    }
  });
}
