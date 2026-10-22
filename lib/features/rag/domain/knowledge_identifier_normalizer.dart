import 'knowledge_document.dart';

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
  static final _faultCodePattern = RegExp(
    r'\b(?:[a-z][.\s_-]*\d+|[a-z]+\.\d+)\b',
    caseSensitive: false,
  );
  static final _labelledFaultPattern = RegExp(
    r'\b(?:fault|error|message)(?:\s+code)?\s+'
    r'([a-z]+[._-]*\d+)\b',
    caseSensitive: false,
  );

  /// Distinguishes fault references from prose such as "pressure 2 bar",
  /// product names such as "Vitocal 252-A", and part names such as "CR2032".
  Set<String> extractFaultCodes(String text) {
    return {
      for (final match in _faultCodePattern.allMatches(text))
        normalize(match.group(0)!)!,
      for (final match in _labelledFaultPattern.allMatches(text))
        normalize(match.group(1)!)!,
    };
  }

  Set<String> extract(String text) {
    return _identifierPattern
        .allMatches(text)
        .map((match) => normalize(match.group(0)!))
        .whereType<String>()
        .toSet();
  }

  /// Identity comes from the record, never from faults mentioned in its prose.
  Set<String> documentIdentifiers(KnowledgeDocument document) {
    if (document.metadata['code'] case final String code) {
      final identifiers = extract(code);
      if (identifiers.isNotEmpty) return identifiers;
    }
    return extract('${document.id} ${document.title}');
  }

  String? normalize(String identifier) {
    final trimmed = identifier.trim();
    if (!_wholeIdentifierPattern.hasMatch(trimmed)) {
      return null;
    }
    return trimmed.replaceAll(_nonAlphaNumericPattern, '').toUpperCase();
  }
}
