import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../domain/document_source.dart';
import '../domain/ingest_documents_use_case.dart';
import 'flutter_gemma_rag_sqlite_repository.dart';

/// Reuses completed SQLite embeddings until the bundled knowledge changes.
class PersistentKnowledgeIndex {
  PersistentKnowledgeIndex({
    required AssetBundle assetBundle,
    required this.assetDirectory,
    required this.databasePath,
    required this.embeddingIdentity,
    required DocumentSource documentSource,
    required IngestDocumentsUseCase ingestDocuments,
    required FlutterGemmaRagSqliteRepository ragRepository,
  }) : _assetBundle = assetBundle,
       _documentSource = documentSource,
       _ingestDocuments = ingestDocuments,
       _ragRepository = ragRepository;

  static const _indexFormatVersion = '1';

  final AssetBundle _assetBundle;
  final String assetDirectory;
  final String databasePath;
  final String embeddingIdentity;
  final DocumentSource _documentSource;
  final IngestDocumentsUseCase _ingestDocuments;
  final FlutterGemmaRagSqliteRepository _ragRepository;
  Future<void>? _preparing;

  Future<void> prepare({
    void Function(DocumentIngestionProgress progress)? onProgress,
  }) {
    return _preparing ??= _prepare(onProgress: onProgress).whenComplete(() {
      _preparing = null;
    });
  }

  Future<void> _prepare({
    void Function(DocumentIngestionProgress progress)? onProgress,
  }) async {
    final fingerprint = await _fingerprint();
    final documents = await _documentSource.loadDocuments();
    final markerFile = File('$databasePath.index.json');
    await _ragRepository.initialize();

    final marker = await _readMarker(markerFile);
    if (marker != null &&
        marker['fingerprint'] == fingerprint &&
        marker['documentCount'] == documents.length &&
        await _ragRepository.indexedDocumentCount() == documents.length) {
      _ragRepository.restoreIdentifiers(documents);
      onProgress?.call(
        DocumentIngestionProgress(
          stage: DocumentIngestionStage.ready,
          documentCount: documents.length,
        ),
      );
      return;
    }

    await _ragRepository.clearIndex();
    await _ingestDocuments.indexDocuments(documents, onProgress: onProgress);
    final indexedCount = await _ragRepository.indexedDocumentCount();
    if (indexedCount != documents.length) {
      throw StateError(
        'Knowledge-base index contains $indexedCount of ${documents.length} documents.',
      );
    }
    await _writeMarker(markerFile, fingerprint, indexedCount);
  }

  Future<String> _fingerprint() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_assetBundle);
    final paths = manifest.listAssets().where((path) {
      if (!path.startsWith(assetDirectory) || !path.endsWith('.json')) {
        return false;
      }
      final name = path.substring(assetDirectory.length);
      return name.isNotEmpty && !name.contains('/');
    }).toList()..sort();
    if (paths.isEmpty) {
      throw StateError(
        'No knowledge-base JSON assets found in "$assetDirectory".',
      );
    }
    final parts = <String>[_indexFormatVersion, embeddingIdentity];
    for (final path in paths) {
      final data = await _assetBundle.load(path);
      parts.add(path);
      parts.add(
        sha256
            .convert(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            )
            .toString(),
      );
    }
    return sha256.convert(utf8.encode(parts.join('\n'))).toString();
  }

  Future<Map<String, dynamic>?> _readMarker(File markerFile) async {
    if (!await markerFile.exists()) return null;
    final Object? data;
    try {
      data = jsonDecode(await markerFile.readAsString());
    } on FormatException catch (error) {
      debugPrint('Rebuilding invalid knowledge-base index marker: $error');
      return null;
    }
    if (data is! Map<String, dynamic> ||
        data['fingerprint'] is! String ||
        data['documentCount'] is! int) {
      debugPrint(
        'Rebuilding invalid knowledge-base index marker "${markerFile.path}".',
      );
      return null;
    }
    return data;
  }

  Future<void> _writeMarker(
    File markerFile,
    String fingerprint,
    int count,
  ) async {
    final temporaryFile = File('${markerFile.path}.tmp');
    await temporaryFile.writeAsString(
      jsonEncode({'fingerprint': fingerprint, 'documentCount': count}),
      flush: true,
    );
    await temporaryFile.rename(markerFile.path);
  }
}
