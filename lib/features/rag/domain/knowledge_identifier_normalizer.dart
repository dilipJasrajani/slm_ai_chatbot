/// Normalizes technical identifiers such as F.838 and F838 for exact matching.
class KnowledgeIdentifierNormalizer {
  const KnowledgeIdentifierNormalizer();

  static final _identifierPattern = RegExp(
    r'\b[a-z]+(?:[.\s_-]*\d+)\b',
    caseSensitive: false,
  );
  static final _wholeIdentifierPattern = RegExp(
    r'^[a-z]+(?:[.\s_-]*\d+)$',
    caseSensitive: false,
  );
  static final _nonAlphaNumericPattern = RegExp(r'[^a-zA-Z0-9]');

  Set<String> extract(String text) {
    return _identifierPattern
        .allMatches(text)
        .map((match) => normalize(match.group(0)!))
        .whereType<String>()
        .toSet();
  }

  String? normalize(String identifier) {
    final trimmed = identifier.trim();
    if (!_wholeIdentifierPattern.hasMatch(trimmed)) {
      return null;
    }
    return trimmed.replaceAll(_nonAlphaNumericPattern, '').toUpperCase();
  }
}
