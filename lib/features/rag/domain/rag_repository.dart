import 'rag_document.dart';
import 'rag_search_result.dart';

/// Indexes searchable documents and returns vector-search matches.
abstract class RagRepository {
  Future<void> initialize();

  Future<void> indexDocuments(Iterable<RagDocument> documents);

  Future<List<RagSearchResult>> search({
    required String query,
    int topK = 1,
    double threshold = 0.0,
  });
}
