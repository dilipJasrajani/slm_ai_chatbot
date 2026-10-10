import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slm_ai_chatbot/features/rag/data/json_document_source.dart';
import 'package:slm_ai_chatbot/features/rag/domain/document_context_builder.dart';
import 'package:slm_ai_chatbot/features/rag/domain/knowledge_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real fault and procedure retain instructions in a smaller prompt',
    () async {
      final documents = await JsonDocumentSource(
        assetBundle: rootBundle,
        assetPath: 'assets/knowledge_base/kb_mobile_v1_1.json',
      ).loadDocuments();
      final selected = [
        for (final id in ['card:msg:f_74', 'card:proc:fill-heating-system'])
          documents.singleWhere((document) => document.id == id),
      ];

      final context = const DocumentContextBuilder().build(selected);

      expect(context, contains('Hydraulic system pressure too low'));
      expect(context, contains('Flush the heating system thoroughly'));
      expect(context, contains('Do not use antifreeze'));
      expect(context, contains('Source pages: 81, 84'));
      expect(context, isNot(contains('search_text')));
      expect(
        context.length,
        lessThan(
          selected.fold<int>(0, (length, doc) => length + doc.content.length) ~/
              2,
        ),
      );
    },
  );

  test('builds deterministic context from multiple generic documents', () {
    const documents = [
      KnowledgeDocument(
        id: 'network-guide',
        title: 'Network guide',
        content: 'Check that Wi-Fi is enabled.',
        metadata: {'type': 'guide', 'priority': 1},
      ),
      KnowledgeDocument(
        id: 'faq-1',
        title: 'Connection FAQ',
        content: 'Retry the connection.',
        metadata: {'type': 'faq'},
      ),
    ];

    final context = const DocumentContextBuilder().build(documents);

    expect(context, contains('Knowledge Document 1'));
    expect(context, contains('Title:\nnetwork-guide Network guide'));
    expect(context, contains('Title:\nfaq-1 Connection FAQ'));
    expect(context, contains('Content:\nCheck that Wi-Fi is enabled.'));
    expect(context, contains('priority: 1\ntype: guide'));
    expect(context, contains('Knowledge Document 2'));
    expect(const DocumentContextBuilder().build(documents), context);
  });

  test('includes measures in grounded context when present', () {
    const documents = [
      KnowledgeDocument(
        id: 'network-guide',
        title: 'Network guide',
        content: 'Check that Wi-Fi is enabled.',
        measures: 'Reconnect the device to Wi-Fi.',
        metadata: {'type': 'guide'},
      ),
    ];

    final context = const DocumentContextBuilder().build(documents);

    expect(
      context,
      contains(
        'Content:\nCheck that Wi-Fi is enabled.'
        '\n\nMeasures:\nReconnect the device to Wi-Fi.'
        '\n\nMetadata:\ntype: guide',
      ),
    );
  });

  test('returns empty context for no documents', () {
    expect(const DocumentContextBuilder().build(const []), isEmpty);
  });

  test(
    'uses factual text and pages without duplicating search-only fields',
    () {
      final record = {
        'id': 'card:msg:f_74',
        'title': 'FAULT F.74',
        'text':
            'Code: F.74\nCause: Hydraulic pressure too low\n'
            'Measures: Top up with water and vent the system.',
        'search_text': 'Very long retrieval terms',
        'phrasings': ['A hypothetical pressure question'],
        'measures': [
          {'text': 'Top up with water and vent the system.'},
        ],
        'pages': [106],
      };
      final document = KnowledgeDocument(
        id: 'card:msg:f_74',
        title: 'FAULT F.74',
        content: jsonEncode(record),
        metadata: const {
          'code': 'F.74',
          'pages': [106],
        },
      );

      final context = const DocumentContextBuilder().build([document]);

      expect(context, contains('Cause: Hydraulic pressure too low'));
      expect(
        context,
        contains('Measures: Top up with water and vent the system.'),
      );
      expect(context, contains('Source pages: 106'));
      expect(context, isNot(contains('Very long retrieval terms')));
      expect(context, isNot(contains('A hypothetical pressure question')));
      expect(context, isNot(contains('"measures"')));
      expect(context.length, lessThan(document.content.length));
    },
  );

  test('retains unknown-schema factual fields without retrieval phrasings', () {
    final document = KnowledgeDocument(
      id: 'pump',
      title: 'Pump',
      content: jsonEncode({
        'id': 'pump',
        'title': 'Pump',
        'details': {'cause': 'Blocked impeller'},
        'steps': ['Isolate power', 'Inspect impeller'],
        'phrasings': ['fictional prompt'],
      }),
      metadata: const {},
    );

    final context = const DocumentContextBuilder().build([document]);

    expect(context, contains('Blocked impeller'));
    expect(context, contains('Isolate power'));
    expect(context, isNot(contains('fictional prompt')));
  });

  test('keeps additional factual fields next to a summary text', () {
    final document = KnowledgeDocument(
      id: 'pressure',
      title: 'Pressure',
      content: jsonEncode({
        'id': 'pressure',
        'text': 'Pressure guidance.',
        'limits': {'minimum_bar': 1.0},
        'search_text': 'Low gauge',
      }),
      metadata: const {},
    );

    final context = const DocumentContextBuilder().build([document]);

    expect(context, contains('Pressure guidance.'));
    expect(context, contains('"minimum_bar":1.0'));
    expect(context, isNot(contains('Low gauge')));
  });
}
