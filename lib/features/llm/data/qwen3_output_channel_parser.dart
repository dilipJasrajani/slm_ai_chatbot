class Qwen3OutputChannelParser {
  const Qwen3OutputChannelParser({this.onDiagnostics});

  final void Function(String summary)? onDiagnostics;

  static const _terminalRouteLabels = {'CHAT', 'KNOWLEDGE'};
  static const _channelMarkers = ['<|channel|>', '<|channel>', '<channel|>'];
  static const _thoughtMarkers = [
    '<|channel|>thought',
    '<|channel>thought',
    '<channel|>thought',
  ];
  static const _finalMarkers = [
    '<|channel|>final',
    '<|channel>final',
    '<channel|>final',
  ];
  static const _markers = [
    ..._thoughtMarkers,
    ..._finalMarkers,
    ..._channelMarkers,
  ];

  Stream<String> parse(Stream<String> rawOutput) async* {
    var channel = _OutputChannel.undecided;
    var buffer = '';
    var terminalRouteCandidate = '';
    var thoughtChannelClosed = false;
    final ordinaryOutput = StringBuffer();
    var unmarkedCharacters = 0;
    var streamPostThink = false;
    final channels = <String>[];
    var channelCount = 0;
    var thinkTags = 0;
    var endTokens = 0;
    final clock = onDiagnostics == null ? null : (Stopwatch()..start());
    Duration? firstThinkClose;
    Duration? firstPostThinkText;

    final filteredOutput = _withoutThinkTags(
      _withoutEndOfTextTokens(rawOutput, onEndToken: () => endTokens++),
      onThinkTag: () => thinkTags++,
      onThinkClose: () => firstThinkClose ??= clock?.elapsed,
      onPostThinkText: () => firstPostThinkText ??= clock?.elapsed,
    );
    await for (final segment in filteredOutput) {
      // Hold pre-think text so a later final-channel marker can still hide it.
      if (segment.afterThink &&
          channel == _OutputChannel.undecided &&
          ordinaryOutput.isEmpty &&
          buffer.isEmpty) {
        streamPostThink = true;
      }
      buffer += segment.text;

      while (buffer.isNotEmpty) {
        final markerIndex = _nextMarkerIndex(buffer);
        if (markerIndex != -1) {
          final content = buffer.substring(0, markerIndex);
          if (channel == _OutputChannel.finalAnswer && content.isNotEmpty) {
            yield content;
          } else if (channel == _OutputChannel.undecided) {
            unmarkedCharacters += content.length;
            if (streamPostThink) {
              yield content;
            } else {
              ordinaryOutput.write(content);
            }
          }

          final marker = _markerAt(buffer, markerIndex)!;
          channelCount++;
          if (channels.length < 12) {
            channels.add(
              _finalMarkers.contains(marker)
                  ? 'final'
                  : _thoughtMarkers.contains(marker)
                  ? 'thought'
                  : 'delimiter',
            );
          }
          terminalRouteCandidate = '';
          thoughtChannelClosed =
              channel == _OutputChannel.thought &&
              _channelMarkers.contains(marker);
          channel = _finalMarkers.contains(marker)
              ? _OutputChannel.finalAnswer
              : _OutputChannel.thought;
          buffer = buffer.substring(markerIndex + marker.length);
          continue;
        }

        final prefixLength = _markerPrefixSuffixLength(buffer);
        final contentLength = buffer.length - prefixLength;
        if (contentLength > 0 && channel == _OutputChannel.finalAnswer) {
          yield buffer.substring(0, contentLength);
        } else if (contentLength > 0 && channel == _OutputChannel.thought) {
          final content = buffer.substring(0, contentLength);
          final answerStart = thoughtChannelClosed
              ? _unmarkedFinalAnswerStart(content)
              : -1;
          if (answerStart != -1) {
            channel = _OutputChannel.finalAnswer;
            thoughtChannelClosed = false;
            terminalRouteCandidate = '';
            if (answerStart < content.length) {
              yield content.substring(answerStart);
            }
          } else {
            terminalRouteCandidate = _routeLabelPrefix(
              '$terminalRouteCandidate$content',
            );
          }
        } else if (contentLength > 0 && channel == _OutputChannel.undecided) {
          final content = buffer.substring(0, contentLength);
          unmarkedCharacters += content.length;
          if (streamPostThink) {
            yield content;
          } else {
            ordinaryOutput.write(content);
          }
        }
        buffer = buffer.substring(contentLength);
        break;
      }
    }

    if (channel == _OutputChannel.undecided) {
      final output = streamPostThink
          ? buffer
          : ordinaryOutput.toString() + buffer;
      if (output.isNotEmpty) {
        yield output;
      }
      unmarkedCharacters += buffer.length;
    } else if (channel == _OutputChannel.finalAnswer &&
        buffer.isNotEmpty &&
        _markerPrefixSuffixLength(buffer) == 0) {
      yield buffer;
    } else if (channel == _OutputChannel.thought) {
      final terminalLabel = terminalRouteCandidate.trim();
      if (_terminalRouteLabels.contains(terminalLabel)) {
        yield terminalLabel;
      }
    }
    onDiagnostics?.call(
      'Qwen output shape: channels=${channels.isEmpty ? 'none' : channels.join('>')} '
      '($channelCount total, first 12 shown), '
      'thinkTags=$thinkTags, endTokens=$endTokens, '
      'unmarkedPrefixCharacters=$unmarkedCharacters, '
      'sinceParserStart: thinkCloseMs=${firstThinkClose?.inMilliseconds ?? 'none'}, '
      'firstPostThinkTextMs=${firstPostThinkText?.inMilliseconds ?? 'none'}',
    );
  }

  int _nextMarkerIndex(String value) {
    var earliest = -1;
    for (final marker in _markers) {
      final index = value.indexOf(marker);
      if (index != -1 && (earliest == -1 || index < earliest)) {
        earliest = index;
      }
    }
    return earliest;
  }

  String? _markerAt(String value, int index) {
    for (final marker in _markers) {
      if (value.startsWith(marker, index)) {
        return marker;
      }
    }
    return null;
  }

  int _markerPrefixSuffixLength(String value) {
    final maximumMarkerLength = _markers
        .map((marker) => marker.length)
        .reduce((first, second) => first > second ? first : second);
    final maximumLength = value.length < maximumMarkerLength
        ? value.length
        : maximumMarkerLength;

    for (var length = maximumLength; length > 0; length--) {
      final suffix = value.substring(value.length - length);
      if (_markers.any((marker) => marker.startsWith(suffix))) {
        return length;
      }
    }
    return 0;
  }

  String _routeLabelPrefix(String value) {
    final trimmed = value.trim();
    return _terminalRouteLabels.any((label) => label.startsWith(trimmed))
        ? value
        : '';
  }

  int _unmarkedFinalAnswerStart(String value) {
    var index = 0;
    var containsLineBreak = false;
    while (index < value.length) {
      final character = value[index];
      if (character == '\n') {
        containsLineBreak = true;
      }
      if (character != ' ' &&
          character != '\t' &&
          character != '\r' &&
          character != '\n') {
        break;
      }
      index++;
    }
    return containsLineBreak ? index : -1;
  }

  Stream<({String text, bool afterThink})> _withoutThinkTags(
    Stream<String> rawOutput, {
    required void Function() onThinkTag,
    required void Function() onThinkClose,
    required void Function() onPostThinkText,
  }) async* {
    const openingTag = '<think>';
    const closingTag = '</think>';
    var buffer = '';
    var insideThinkTag = false;
    var closedThinkTag = false;

    await for (final chunk in rawOutput) {
      buffer += chunk;

      while (buffer.isNotEmpty) {
        if (insideThinkTag) {
          final closingTagIndex = buffer.indexOf(closingTag);
          if (closingTagIndex != -1) {
            buffer = buffer.substring(closingTagIndex + closingTag.length);
            insideThinkTag = false;
            closedThinkTag = true;
            onThinkClose();
            continue;
          }
          buffer = _tagPrefixSuffix(buffer, closingTag);
          break;
        }

        final openingTagIndex = buffer.indexOf(openingTag);
        if (openingTagIndex != -1) {
          if (openingTagIndex > 0) {
            final content = buffer.substring(0, openingTagIndex);
            if (closedThinkTag && content.trim().isNotEmpty) {
              onPostThinkText();
            }
            yield (text: content, afterThink: closedThinkTag);
          }
          buffer = buffer.substring(openingTagIndex + openingTag.length);
          insideThinkTag = true;
          onThinkTag();
          continue;
        }

        final suffix = _tagPrefixSuffix(buffer, openingTag);
        final contentLength = buffer.length - suffix.length;
        if (contentLength > 0) {
          final content = buffer.substring(0, contentLength);
          if (closedThinkTag && content.trim().isNotEmpty) {
            onPostThinkText();
          }
          yield (text: content, afterThink: closedThinkTag);
        }
        buffer = suffix;
        break;
      }
    }
  }

  String _tagPrefixSuffix(String value, String tag) {
    final maximumLength = value.length < tag.length ? value.length : tag.length;
    for (var length = maximumLength; length > 0; length--) {
      final suffix = value.substring(value.length - length);
      if (tag.startsWith(suffix)) {
        return suffix;
      }
    }
    return '';
  }

  Stream<String> _withoutEndOfTextTokens(
    Stream<String> rawOutput, {
    required void Function() onEndToken,
  }) async* {
    const token = '<|endoftext|>';
    var buffer = '';

    await for (final chunk in rawOutput) {
      buffer += chunk;

      while (buffer.isNotEmpty) {
        final tokenIndex = buffer.indexOf(token);
        if (tokenIndex != -1) {
          if (tokenIndex > 0) {
            yield buffer.substring(0, tokenIndex);
          }
          buffer = buffer.substring(tokenIndex + token.length);
          onEndToken();
          continue;
        }

        final suffix = _tagPrefixSuffix(buffer, token);
        final contentLength = buffer.length - suffix.length;
        if (contentLength > 0) {
          yield buffer.substring(0, contentLength);
        }
        buffer = suffix;
        break;
      }
    }
  }
}

enum _OutputChannel { undecided, thought, finalAnswer }
