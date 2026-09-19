import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/llm/local_llm_service.dart';
import '../domain/model/local_model_manager.dart';
import '../domain/model/model_status.dart';
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
      final result = await widget.ragProofOfConcept.run();
      if (mounted) {
        setState(() {
          _ragStatus = result == null
              ? 'No relevant document was found.'
              : 'Retrieved ${result.id}:\n${result.content}';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _ragStatus = 'Local RAG error: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isRunningRag = false);
      }
    }
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
        child: Padding(
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
                      ? 'Indexing Local RAG Documents...'
                      : 'Run Local RAG Proof of Concept',
                ),
              ),
              if (_ragStatus != null) ...[
                const SizedBox(height: 8),
                Text(_ragStatus!),
              ],
              const SizedBox(height: 24),
              const Text('Response:'),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(_generationError ?? modelError ?? _response),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
