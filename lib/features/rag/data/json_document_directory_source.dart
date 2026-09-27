import 'package:flutter/services.dart';

import '../domain/document_source.dart';
import '../domain/knowledge_document.dart';
import 'json_document_source.dart';

/// Loads direct JSON assets in a directory before any documents are indexed.
class JsonDocumentDirectorySource implements DocumentSource {
  JsonDocumentDirectorySource({
    required AssetBundle assetBundle,
    required this.assetDirectory,
  }) : _assetBundle = assetBundle;

  final AssetBundle _assetBundle;
  final String assetDirectory;

  @override
  Future<List<KnowledgeDocument>> loadDocuments() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_assetBundle);
    final paths = manifest.listAssets().where((path) {
      if (!path.startsWith(assetDirectory) || !path.endsWith('.json')) {
        return false;
      }
      final filename = path.substring(assetDirectory.length);
      return filename.isNotEmpty && !filename.contains('/');
    }).toList()..sort();

    if (paths.isEmpty) {
      throw StateError(
        'No knowledge-base JSON assets found in "$assetDirectory".',
      );
    }

    final documents = <KnowledgeDocument>[];
    final firstAssetById = <String, String>{};
    for (final path in paths) {
      final List<KnowledgeDocument> fileDocuments;
      try {
        fileDocuments = await JsonDocumentSource(
          assetBundle: _assetBundle,
          assetPath: path,
        ).loadDocuments();
      } on FormatException catch (error) {
        throw FormatException(
          'Invalid knowledge-base asset "$path": ${error.message}',
          error.source,
          error.offset,
        );
      }
      for (final document in fileDocuments) {
        final firstAsset = firstAssetById[document.id];
        if (firstAsset != null && firstAsset != path) {
          throw FormatException(
            'Duplicate knowledge document ID "${document.id}" in '
            '"$firstAsset" and "$path".',
          );
        }
        firstAssetById[document.id] = path;
        documents.add(document);
      }
    }
    return List.unmodifiable(documents);
  }
}
