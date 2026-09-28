import 'rag_document.dart';
import 'rag_search_result.dart';

/// Indexes searchable documents and retrieves semantic or exact source matches.
abstract class RagRepository {
  Future<void> initialize();

  Future<void> indexDocuments(Iterable<RagDocument> documents);

  /// [topK] limits semantic matches; exact source matches may be included first.
  Future<List<RagSearchResult>> search({
    required String query,
    String? exactMatchQuery,
    int topK = 1,
    double threshold = 0.0,
  });
}
