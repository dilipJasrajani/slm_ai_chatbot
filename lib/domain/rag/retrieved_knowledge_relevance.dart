import 'knowledge_document.dart';
import 'rag_search_result.dart';

class RetrievedKnowledgeRelevance {
  const RetrievedKnowledgeRelevance();

  static final _tokenPattern = RegExp(r'[a-z0-9]+', caseSensitive: false);
  static const _ignoredTokens = {
    'about',
    'after',
    'again',
    'also',
    'and',
    'are',
    'can',
    'did',
    'does',
    'for',
    'from',
    'how',
    'i',
    'in',
    'is',
    'it',
    'me',
    'my',
    'of',
    'on',
    'please',
    'should',
    'tell',
    'that',
    'the',
    'this',
    'to',
    'what',
    'why',
    'with',
    'you',
  };

  List<KnowledgeDocument> relevantDocuments({
    required String question,
    required Iterable<RagSearchResult> results,
  }) {
    final questionTokens = _meaningfulTokens(question);
    return results
        .where(
          (result) =>
              _sharedTokenCount(
                    questionTokens,
                    _documentTokens(result.document),
                  ) >=
                  2 ||
              _sharesIdentifier(
                questionTokens,
                _documentTokens(result.document),
              ),
        )
        .map((result) => result.document)
        .toList(growable: false);
  }

  Set<String> _documentTokens(KnowledgeDocument document) {
    return _meaningfulTokens(
      '${document.id} ${document.title} ${document.content} ${document.metadata.values.join(' ')}',
    );
  }

  Set<String> _meaningfulTokens(String text) {
    return _tokenPattern
        .allMatches(text.toLowerCase())
        .map((match) => match.group(0)!)
        .where((token) => token.length >= 3 && !_ignoredTokens.contains(token))
        .map(_stem)
        .toSet();
  }

  String _stem(String token) {
    if (token.endsWith('ing') && token.length > 5) {
      return token.substring(0, token.length - 3);
    }
    if (token.endsWith('ed') && token.length > 4) {
      return token.substring(0, token.length - 2);
    }
    if (token.endsWith('s') && token.length > 4) {
      return token.substring(0, token.length - 1);
    }
    return token;
  }

  int _sharedTokenCount(
    Set<String> questionTokens,
    Set<String> documentTokens,
  ) {
    return questionTokens
        .where(
          (questionToken) => documentTokens.any(
            (documentToken) => _sameConcept(questionToken, documentToken),
          ),
        )
        .length;
  }

  bool _sharesIdentifier(
    Set<String> questionTokens,
    Set<String> documentTokens,
  ) {
    return questionTokens.any(
      (questionToken) =>
          questionToken.contains(RegExp(r'\d')) &&
          documentTokens.contains(questionToken),
    );
  }

  bool _sameConcept(String first, String second) {
    if (first == second) return true;
    var sharedPrefixLength = 0;
    while (sharedPrefixLength < first.length &&
        sharedPrefixLength < second.length &&
        first[sharedPrefixLength] == second[sharedPrefixLength]) {
      sharedPrefixLength++;
    }
    return sharedPrefixLength >= 6;
  }
}
