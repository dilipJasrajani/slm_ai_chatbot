import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/llm/local_llm_service.dart';
import '../domain/model/local_model_manager.dart';
import '../domain/model/model_status.dart';
import '../domain/rag/ingest_documents_use_case.dart';
import '../domain/rag/knowledge_document.dart';
import '../domain/rag/technical_support_rag_proof_of_concept.dart';

class LocalInferenceScreen extends StatefulWidget {
  const LocalInferenceScreen({
    required this.modelManager,
    required this.llmService,
    required this.ragProofOfConcept,
    super.key,
  });

  final LocalModelManager modelManager;
  final LocalLlmService llmService;
  final TechnicalSupportRagProofOfConcept ragProofOfConcept;

  @override
  State<LocalInferenceScreen> createState() => _LocalInferenceScreenState();
}

class _LocalInferenceScreenState extends State<LocalInferenceScreen> {
  static const _prompt = 'Hello! Introduce yourself in one sentence.';

  late ModelState _modelState;
  StreamSubscription<ModelState>? _modelStateSubscription;
  var _isGenerating = false;
  var _isRunningRag = false;
  var _response = '';
  String? _generationError;
  String? _ragStatus;
  String? _ragQuestion;
  List<KnowledgeDocument> _retrievedDocuments = const [];
  String? _ragAnswer;

  @override
  void initState() {
    super.initState();
    _modelState = widget.modelManager.state;
    _modelStateSubscription = widget.modelManager.states.listen((state) {
      if (mounted) {
        setState(() => _modelState = state);
      }
    });
    unawaited(widget.modelManager.ensureReady());
  }

  @override
  void dispose() {
    unawaited(_modelStateSubscription?.cancel());
    unawaited(widget.llmService.dispose());
    super.dispose();
  }

  Future<void> _generateResponse() async {
    if (_isGenerating || _modelState.status != ModelStatus.ready) {
      return;
    }

    setState(() {
      _isGenerating = true;
      _response = '';
      _generationError = null;
    });

    try {
      await for (final chunk in widget.llmService.generate(_prompt)) {
        if (!mounted) {
          return;
        }
        setState(() => _response += chunk);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _generationError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _stopGeneration() async {
    try {
      await widget.llmService.stop();
    } catch (error) {
      if (mounted) {
        setState(() => _generationError = error.toString());
      }
    }
  }

  Future<void> _runRagProofOfConcept() async {
    if (_isRunningRag) return;

    setState(() {
      _isRunningRag = true;
      _ragStatus = null;
    });

    try {
      final result = await widget.ragProofOfConcept.run(
        onProgress: _showIngestionProgress,
      );
      if (mounted) {
        setState(() {
          _ragQuestion = TechnicalSupportRagProofOfConcept.question;
          _retrievedDocuments = result.documents;
          _ragAnswer = result.answer;
          _ragStatus = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _ragStatus = 'Unable to prepare local knowledge documents.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRunningRag = false);
      }
    }
  }

  void _showIngestionProgress(DocumentIngestionProgress progress) {
    if (!mounted) return;

    final status = switch (progress.stage) {
      DocumentIngestionStage.loading => 'Loading documents...',
      DocumentIngestionStage.loaded =>
        'Loaded ${progress.documentCount} documents.',
      DocumentIngestionStage.indexing =>
        'Indexing ${progress.documentCount} documents...',
      DocumentIngestionStage.ready =>
        'Documents ready: ${progress.documentCount} documents indexed.',
    };
    setState(() => _ragStatus = status);
  }

  @override
  Widget build(BuildContext context) {
    final modelError = _modelState.status == ModelStatus.error
        ? _modelState.errorMessage
        : null;
    final canGenerate =
        _modelState.status == ModelStatus.ready && !_isGenerating;

    return Scaffold(
      appBar: AppBar(title: const Text('Local Gemma Test')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Model status: ${_modelState.status.name}'),
              if (_modelState.status == ModelStatus.downloading)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(
                    value: (_modelState.downloadProgress ?? 0) / 100,
                  ),
                ),
              const SizedBox(height: 24),
              const Text('Prompt:'),
              const SizedBox(height: 8),
              const Text(_prompt),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: canGenerate ? _generateResponse : null,
                child: const Text('Generate Test Response'),
              ),
              if (_isGenerating)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: _stopGeneration,
                    child: const Text('Stop'),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isRunningRag ? null : _runRagProofOfConcept,
                child: Text(
                  _isRunningRag
                      ? 'Preparing Local RAG Answer...'
                      : 'Run Local RAG Question Answering',
                ),
              ),
              if (_ragQuestion != null) ...[
                const SizedBox(height: 16),
                const Text('Question:'),
                Text(_ragQuestion!),
                const SizedBox(height: 8),
                const Text('Retrieved documents:'),
                if (_retrievedDocuments.isEmpty)
                  const Text('No relevant documents found.')
                else
                  ..._retrievedDocuments.map(
                    (document) => Text('${document.title} (${document.id})'),
                  ),
                const SizedBox(height: 8),
                const Text('Answer:'),
                Text(_ragAnswer ?? ''),
              ],
              if (_ragStatus != null) ...[
                const SizedBox(height: 8),
                Text(_ragStatus!),
              ],
              const SizedBox(height: 24),
              const Text('Response:'),
              const SizedBox(height: 8),
              Text(_generationError ?? modelError ?? _response),
            ],
          ),
        ),
      ),
    );
  }
}
