import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

enum AiProfileEvent {
  routerStart,
  routerEnd,
  retrievalQueryStart,
  retrievalQueryEnd,
  searchStart,
  searchEnd,
  embeddingAndVectorSearchStart,
  embeddingAndVectorSearchEnd,
  metadataDecodeStart,
  metadataDecodeEnd,
  groundingStart,
  groundingEnd,
  contextBuildStart,
  contextBuildEnd,
  promptBuildStart,
  promptBuildEnd,
  finalLlmStart,
  firstRawChunk,
  firstParsedChunk,
  firstPresentationText,
  firstRenderedText,
  finalLlmEnd,
  requestEnd,
}

enum AiGenerationPhase { router, finalAnswer }

class AiNativeMetrics {
  const AiNativeMetrics({
    this.inputTokens,
    this.outputTokens,
    this.timeToFirstTokenMs,
    this.tokensPerSecond,
    this.initTimeMs,
  });

  final int? inputTokens;
  final int? outputTokens;
  final double? timeToFirstTokenMs;
  final double? tokensPerSecond;
  final double? initTimeMs;
}

/// Request-scoped debug measurements; the zone keeps existing service APIs intact.
class AiLatencyProfile {
  AiLatencyProfile({required this.requestNumber, void Function(String)? log})
    : _log = log ?? debugPrint {
    _clock.start();
    _write(
      'Request started (${requestNumber == 1 ? 'COLD' : 'WARM'}: '
      'accepted request #$requestNumber)',
    );
  }

  static final Object _zoneKey = Object();

  static AiLatencyProfile? get current =>
      Zone.current[_zoneKey] as AiLatencyProfile?;

  static Future<T> run<T>(
    AiLatencyProfile? profile,
    Future<T> Function() action,
  ) => profile == null
      ? action()
      : runZoned<Future<T>>(action, zoneValues: {_zoneKey: profile});

  final int requestNumber;
  final void Function(String) _log;
  final Stopwatch _clock = Stopwatch();
  final Map<AiProfileEvent, Duration> _events = {};
  final Map<AiGenerationPhase, AiNativeMetrics> _nativeMetrics = {};
  final Map<AiGenerationPhase, String> _nativeUnavailable = {};
  AiGenerationPhase? generationPhase;
  String? route;
  String backend = 'UNKNOWN';
  int? historyMessageCount;
  int? historyCharacters;
  int? routerPromptCharacters;
  int? routerOutputCharacters;
  int? chatPromptCharacters;
  int? ragPromptCharacters;
  int? retrievedContextCharacters;
  int? userQueryCharacters;
  int? retrievedCount;
  int? groundedCount;
  bool routerFallback = false;
  bool _completed = false;

  Duration? elapsedAt(AiProfileEvent event) => _events[event];

  void mark(AiProfileEvent event) {
    _events.putIfAbsent(event, () => _clock.elapsed);
  }

  void firstRawChunk(AiGenerationPhase? phase) {
    if (phase == AiGenerationPhase.finalAnswer) {
      mark(AiProfileEvent.firstRawChunk);
    }
  }

  void firstParsedChunk(AiGenerationPhase? phase, String chunk) {
    if (phase == AiGenerationPhase.finalAnswer && chunk.isNotEmpty) {
      mark(AiProfileEvent.firstParsedChunk);
    }
  }

  void recordNativeMetrics(AiGenerationPhase? phase, AiNativeMetrics metrics) {
    if (phase != null) _nativeMetrics[phase] = metrics;
  }

  void nativeMetricsUnavailable(AiGenerationPhase? phase, String reason) {
    if (phase != null) _nativeUnavailable[phase] = reason;
  }

  bool get isFirstRenderedTextPending =>
      _events.containsKey(AiProfileEvent.firstPresentationText) &&
      !_events.containsKey(AiProfileEvent.firstRenderedText);

  void recordFirstRenderedText() {
    if (!isFirstRenderedTextPending) return;
    mark(AiProfileEvent.firstRenderedText);
    if (_completed) {
      _write(
        'First visible assistant text (post-frame): '
        '${_sinceStart(AiProfileEvent.firstRenderedText)}',
      );
    }
  }

  void complete(String status) {
    if (_completed) return;
    mark(AiProfileEvent.requestEnd);
    _completed = true;
    _write(
      'Request complete: route=${route ?? 'UNKNOWN'}, status=$status, '
      'backend=$backend',
    );
    _write('Total request: ${_sinceStart(AiProfileEvent.requestEnd)}');
    _write(
      'Router: ${_between(AiProfileEvent.routerStart, AiProfileEvent.routerEnd)}'
      '${routerFallback ? ' (fallback used)' : ''}',
    );
    if (route == 'KNOWLEDGE') {
      _write(
        'Retrieval query: ${_between(AiProfileEvent.retrievalQueryStart, AiProfileEvent.retrievalQueryEnd, milliseconds: true)}',
      );
      _write(
        'Embedding + vector search: ${_between(AiProfileEvent.embeddingAndVectorSearchStart, AiProfileEvent.embeddingAndVectorSearchEnd, milliseconds: true)}'
        ' (not separately measurable at current application boundary)',
      );
      _write(
        'Search including preparation/decoding: ${_between(AiProfileEvent.searchStart, AiProfileEvent.searchEnd, milliseconds: true)}',
      );
      _write(
        'Metadata decode: ${_between(AiProfileEvent.metadataDecodeStart, AiProfileEvent.metadataDecodeEnd, milliseconds: true)}',
      );
      _write(
        'Grounding: ${_between(AiProfileEvent.groundingStart, AiProfileEvent.groundingEnd, milliseconds: true)}',
      );
      _write(
        'Context build: ${_between(AiProfileEvent.contextBuildStart, AiProfileEvent.contextBuildEnd, milliseconds: true)}',
      );
      _write(
        'Results: retrieved=${retrievedCount ?? 'Not available'}, '
        'grounded=${groundedCount ?? 'Not available'}',
      );
    }
    _write(
      'Final prompt build: ${_between(AiProfileEvent.promptBuildStart, AiProfileEvent.promptBuildEnd, milliseconds: true)}',
    );
    _write(
      'Final LLM: ${_between(AiProfileEvent.finalLlmStart, AiProfileEvent.finalLlmEnd)}',
    );
    _write(
      'First raw chunk: ${_sinceStart(AiProfileEvent.firstRawChunk)}; '
      'first parsed chunk: ${_sinceStart(AiProfileEvent.firstParsedChunk)}',
    );
    _write(
      'Raw-to-parsed gap: ${_between(AiProfileEvent.firstRawChunk, AiProfileEvent.firstParsedChunk, milliseconds: true)}',
    );
    _write(
      'First presentation text: ${_sinceStart(AiProfileEvent.firstPresentationText)}; '
      'first visible assistant text (post-frame): ${_sinceStart(AiProfileEvent.firstRenderedText)}',
    );
    _write(
      'Prompt characters: router=${routerPromptCharacters ?? 'Not available'}, '
      'router output=${routerOutputCharacters ?? 'Not available'}, '
      'CHAT=${chatPromptCharacters ?? 'Not available'}, '
      'RAG=${ragPromptCharacters ?? 'Not available'}, '
      'history=${historyCharacters ?? 'Not available'} '
      '(${historyMessageCount ?? 'Not available'} messages), '
      'context=${retrievedContextCharacters ?? 'Not available'}, '
      'query=${userQueryCharacters ?? 'Not available'}',
    );
    _writeMetrics('Router', AiGenerationPhase.router);
    _writeMetrics('Final', AiGenerationPhase.finalAnswer);
  }

  String _sinceStart(AiProfileEvent event) {
    final elapsed = _events[event];
    return elapsed == null ? 'Not available' : _format(elapsed);
  }

  String _between(
    AiProfileEvent start,
    AiProfileEvent end, {
    bool milliseconds = false,
  }) {
    final beginning = _events[start];
    final ending = _events[end];
    return beginning == null || ending == null
        ? 'Not available'
        : milliseconds
        ? '${((ending - beginning).inMicroseconds / 1000).toStringAsFixed(2)}ms'
        : _format(ending - beginning);
  }

  String _format(Duration duration) =>
      '${(duration.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3)}s';

  void _writeMetrics(String label, AiGenerationPhase phase) {
    final metrics = _nativeMetrics[phase];
    if (metrics == null) {
      final reason = _nativeUnavailable[phase];
      _write(
        '$label native metrics: Not available'
        '${reason == null ? '' : ' ($reason)'}',
      );
      return;
    }
    _write(
      '$label native metrics: '
      'input=${metrics.inputTokens ?? 'Not available'}, '
      'output=${metrics.outputTokens ?? 'Not available'}, '
      'TTFT=${_formatOptionalMs(metrics.timeToFirstTokenMs)}, '
      'tokens/sec=${metrics.tokensPerSecond?.toStringAsFixed(2) ?? 'Not available'}, '
      'init=${_formatOptionalMs(metrics.initTimeMs)}',
    );
  }

  String _formatOptionalMs(double? value) =>
      value == null ? 'Not available' : '${value.toStringAsFixed(2)}ms';

  void _write(String message) => _log('[AI-PROFILE] #$requestNumber $message');
}
