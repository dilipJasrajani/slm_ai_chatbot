class Qwen3OutputChannelParser {
  const Qwen3OutputChannelParser();

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
    rawOutput = _withoutEndOfTextTokens(_withoutThinkTags(rawOutput));
    var channel = _OutputChannel.undecided;
    var buffer = '';
    var terminalRouteCandidate = '';
    var thoughtChannelClosed = false;
    final ordinaryOutput = StringBuffer();

    await for (final chunk in rawOutput) {
      buffer += chunk;

      while (buffer.isNotEmpty) {
        final markerIndex = _nextMarkerIndex(buffer);
        if (markerIndex != -1) {
          final content = buffer.substring(0, markerIndex);
          if (channel == _OutputChannel.finalAnswer && content.isNotEmpty) {
            yield content;
          } else if (channel == _OutputChannel.undecided) {
            ordinaryOutput.write(content);
          }

          final marker = _markerAt(buffer, markerIndex)!;
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
          ordinaryOutput.write(buffer.substring(0, contentLength));
        }
        buffer = buffer.substring(contentLength);
        break;
      }
    }

    if (channel == _OutputChannel.undecided) {
      final output = ordinaryOutput.toString() + buffer;
      if (output.isNotEmpty) {
        yield output;
      }
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

  Stream<String> _withoutThinkTags(Stream<String> rawOutput) async* {
    const openingTag = '<think>';
    const closingTag = '</think>';
    var buffer = '';
    var insideThinkTag = false;

    await for (final chunk in rawOutput) {
      buffer += chunk;

      while (buffer.isNotEmpty) {
        if (insideThinkTag) {
          final closingTagIndex = buffer.indexOf(closingTag);
          if (closingTagIndex != -1) {
            buffer = buffer.substring(closingTagIndex + closingTag.length);
            insideThinkTag = false;
            continue;
          }
          buffer = _tagPrefixSuffix(buffer, closingTag);
          break;
        }

        final openingTagIndex = buffer.indexOf(openingTag);
        if (openingTagIndex != -1) {
          if (openingTagIndex > 0) {
            yield buffer.substring(0, openingTagIndex);
          }
          buffer = buffer.substring(openingTagIndex + openingTag.length);
          insideThinkTag = true;
          continue;
        }

        final suffix = _tagPrefixSuffix(buffer, openingTag);
        final contentLength = buffer.length - suffix.length;
        if (contentLength > 0) {
          yield buffer.substring(0, contentLength);
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

  Stream<String> _withoutEndOfTextTokens(Stream<String> rawOutput) async* {
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
