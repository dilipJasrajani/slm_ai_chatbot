import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/domain/chat/chat_route.dart';
import 'package:slm_ai_chatbot/domain/chat/chat_route_parser.dart';

void main() {
  const parser = ChatRouteParser();

  test('parses clear CHAT labels with common formatting', () {
    for (final value in [
      'CHAT',
      'chat',
      ' CHAT',
      'CHAT.',
      '- CHAT',
      '- CHAT for greetings, gratitude, or casual conversation.',
      'CHAT because this is casual conversation.',
    ]) {
      expect(parser.parse(value), ChatRoute.chat, reason: value);
    }
  });

  test('parses clear KNOWLEDGE labels with common formatting', () {
    for (final value in [
      'KNOWLEDGE',
      'knowledge',
      ' KNOWLEDGE',
      'KNOWLEDGE.',
      '- KNOWLEDGE',
      'KNOWLEDGE because technical information may be required.',
      r'KNOWLEDGE\n',
    ]) {
      expect(parser.parse(value), ChatRoute.knowledge, reason: value);
    }
  });

  test('defaults ambiguous and unexpected output to knowledge', () {
    for (final value in [
      'The correct answer is CHAT',
      'The correct answer is KNOWLEDGE',
      'CHAT and KNOWLEDGE',
      'random response',
      '',
    ]) {
      expect(parser.parse(value), ChatRoute.knowledge, reason: value);
    }
  });
}
