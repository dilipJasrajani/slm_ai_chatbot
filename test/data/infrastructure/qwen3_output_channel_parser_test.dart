import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/data/infrastructure/qwen3_output_channel_parser.dart';

void main() {
  const parser = Qwen3OutputChannelParser();

  test('emits clean final channel text', () async {
    final output = await parser
        .parse(Stream.value('<|channel|>finalThe boiler is ready.'))
        .join();

    expect(output, 'The boiler is ready.');
  });

  test('suppresses thought-only output', () async {
    final output = await parser
        .parse(Stream.value('<|channel|>thoughtInternal reasoning.'))
        .join();

    expect(output, isEmpty);
  });

  test('emits only final text after thought output', () async {
    final output = await parser
        .parse(
          Stream.fromIterable([
            '<|channel|>thoughtConsider error E123.',
            '<|channel|>finalRestart the device.',
          ]),
        )
        .join();

    expect(output, 'Restart the device.');
  });

  test('does not emit text before a final channel marker', () async {
    final output = await parser
        .parse(
          Stream.fromIterable([
            'Do not show this preamble.',
            '<|channel|>finalRestart the device.',
          ]),
        )
        .join();

    expect(output, 'Restart the device.');
  });

  test('recognizes channel markers fragmented across chunks', () async {
    final output = await parser
        .parse(
          Stream.fromIterable([
            '<|chan',
            'nel|>thoughtHidden',
            ' reasoning<|chan',
            'nel|>finalVisible answer',
          ]),
        )
        .join();

    expect(output, 'Visible answer');
  });

  test('passes ordinary output without channel markers unchanged', () async {
    final output = await parser
        .parse(Stream.fromIterable(['The ', 'device is ', 'ready.']))
        .join();

    expect(output, 'The device is ready.');
  });

  test('does not leak thought text or markers into final output', () async {
    final output = await parser
        .parse(
          Stream.fromIterable([
            '<|channel|>thoughtNever show this.',
            '<|channel|>finalOnly show this.',
            '<|channel|>thoughtAlso hidden.',
          ]),
        )
        .join();

    expect(output, 'Only show this.');
    expect(output, isNot(contains('thought')));
    expect(output, isNot(contains('hidden')));
    expect(output, isNot(contains('<|channel|>')));
  });

  test(
    'suppresses repeated standalone channel delimiters from Qwen streams',
    () async {
      final output = await parser
          .parse(
            Stream.fromIterable([
              '<|channel|>thought\nOkay<|channel|>',
              '<|channel|>thought the internal response',
              '<|channel|>finalThe visible answer.',
            ]),
          )
          .join();

      expect(output, 'The visible answer.');
      expect(output, isNot(contains('<|channel|>')));
      expect(output, isNot(contains('thought')));
      expect(output, isNot(contains('internal')));
    },
  );

  test('suppresses the LiteRT delimiter variants emitted by Qwen', () async {
    final output = await parser
        .parse(
          Stream.fromIterable([
            '<|channel>thought Okay<channel|><|channel>thought hidden',
            '<channel|><|channel>finalVisible answer.',
          ]),
        )
        .join();

    expect(output, 'Visible answer.');
    expect(output, isNot(contains('thought')));
    expect(output, isNot(contains('<|channel>')));
    expect(output, isNot(contains('<channel|>')));
  });

  test(
    'emits only an exact terminal route label after a thought stream',
    () async {
      final output = await parser
          .parse(
            Stream.fromIterable([
              '<|channel>thoughtHidden routing rationale.<channel|>',
              'CHAT',
            ]),
          )
          .join();

      expect(output, 'CHAT');
      expect(output, isNot(contains('Hidden')));
      expect(output, isNot(contains('thought')));
    },
  );

  test('does not emit unmarked content after a thought stream', () async {
    final output = await parser
        .parse(
          Stream.fromIterable([
            '<|channel>thoughtHidden reasoning.<channel|>',
            'Unmarked answer text',
          ]),
        )
        .join();

    expect(output, isEmpty);
  });

  test(
    'emits an unmarked final answer after the LiteRT thought boundary',
    () async {
      final output = await parser
          .parse(
            Stream.fromIterable([
              '<|channel>thoughtHidden reasoning.<channel|>',
              '\n\n',
              'Hello',
              '! How can I assist you today?',
            ]),
          )
          .join();

      expect(output, 'Hello! How can I assist you today?');
      expect(output, isNot(contains('Hidden')));
      expect(output, isNot(contains('thought')));
    },
  );
}
