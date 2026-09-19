import 'rag_document.dart';
import 'rag_repository.dart';
import 'rag_search_result.dart';

class TechnicalSupportRagProofOfConcept {
  TechnicalSupportRagProofOfConcept(this._repository);

  final RagRepository _repository;

  // static const query = 'The device cannot connect to the network.';
  static const query = 'Seems some sendor is not working.';

  static const documents = [
    RagDocument(
      id: 'error-e123',
      content:
          'Error E123:\n'
          'The device failed to establish a network connection.\n'
          'Possible cause: Network connectivity is unavailable.\n'
          'Resolution: Check the network connection and retry.',
      metadata: {'errorCode': 'E123'},
    ),
    RagDocument(
      id: 'error-e456',
      content:
          'Error E456:\n'
          'The device temperature sensor is not responding.\n'
          'Possible cause: The sensor cable is disconnected.\n'
          'Resolution: Inspect and reconnect the sensor cable.',
      metadata: {'errorCode': 'E456'},
    ),
    RagDocument(
      id: 'error-e789',
      content:
          'Error E789:\n'
          'The device cannot complete a firmware update.\n'
          'Possible cause: The update package is corrupted.\n'
          'Resolution: Download the update package again and restart the update.',
      metadata: {'errorCode': 'E789'},
    ),
  ];

  Future<RagSearchResult?> run() async {
    await _repository.initialize();
    await _repository.indexDocuments(documents);
    final results = await _repository.search(query: query);
    return results.isEmpty ? null : results.first;
  }
}
