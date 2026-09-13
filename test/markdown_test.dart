import 'package:compcri_flutter/core/design.dart';
import 'package:compcri_flutter/core/markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every span in the tree, containers included — emphasis is carried by a
/// parent span whose children inherit the style, so a leaves-only walk misses
/// exactly what these tests are checking.
Iterable<TextSpan> walk(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* walk(child);
  }
}

List<TextSpan> spansOf(WidgetTester tester) => [
  for (final text in tester.widgetList<RichText>(find.byType(RichText)))
    ...walk(text.text),
];

String renderedText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((text) => text.text.toPlainText())
    .join();

Future<void> pumpMarkdown(WidgetTester tester, String source) =>
    tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 300, child: MarkdownText(source)),
          ),
        ),
      ),
    );

void main() {
  // The reply that started this: the model bolds the title, the date and the
  // label, and the bubble used to print every asterisk.
  const reply =
      "I've prepared an event for your confirmation:\n"
      '\n'
      '**Interview**\n'
      'Tomorrow, **September 13, 2026**,\n'
      'from **2:00-3:00 PM**\n'
      '**Location:** Banani, Dhaka\n'
      '\n'
      'Would you like me to create it?';

  testWidgets('renders emphasis instead of printing its syntax', (
    tester,
  ) async {
    await pumpMarkdown(tester, reply);

    final text = renderedText(tester);
    expect(text, isNot(contains('**')));
    expect(text, contains('Interview'));
    expect(text, contains('Location:'));
    expect(text, contains('Banani, Dhaka'));

    final bold = spansOf(tester)
        .where((span) => span.style?.fontWeight == FontWeight.w700)
        .map((span) => span.toPlainText())
        .join('|');
    expect(bold, contains('Interview'));
    expect(bold, contains('September 13, 2026'));
    expect(bold, contains('Location:'));
  });

  testWidgets('keeps single newlines as line breaks', (tester) async {
    await pumpMarkdown(tester, reply);
    expect(renderedText(tester), contains('Tomorrow, September 13, 2026,\n'));
  });

  testWidgets('renders lists, headings, quotes and code', (tester) async {
    await pumpMarkdown(
      tester,
      '# Today\n'
      '- first thing\n'
      '- second thing\n'
      '1. step one\n'
      '> a quoted aside\n'
      'Run `flutter test` now.\n'
      '```\ncode block\n```',
    );

    final text = renderedText(tester);
    for (final syntax in ['# ', '- ', '> ', '`', '```']) {
      expect(text, isNot(contains(syntax)), reason: 'leaked $syntax');
    }
    expect(text, contains('first thing'));
    expect(text, contains('step one'));
    expect(text, contains('a quoted aside'));
    expect(text, contains('code block'));
    // Bullets get a real marker, ordered items keep their number.
    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('1.'), findsOneWidget);
  });

  testWidgets('leaves unknown syntax exactly as written', (tester) async {
    await pumpMarkdown(tester, 'A lone * star and 3 * 4 = 12');
    expect(renderedText(tester), 'A lone * star and 3 * 4 = 12');
  });

  group('half-typed syntax', () {
    test('drops a marker still being keyed', () {
      expect(StreamedMarkdown.repair('Ready **'), 'Ready ');
      expect(StreamedMarkdown.repair('Ready **Inter'), 'Ready **Inter**');
      expect(StreamedMarkdown.repair('a `flut'), 'a `flut`');
    });

    test('closes a fence that has not arrived yet', () {
      expect(StreamedMarkdown.repair('```\nrun'), '```\nrun\n```');
    });

    test('leaves balanced text alone', () {
      expect(StreamedMarkdown.repair('**Interview**'), '**Interview**');
      expect(StreamedMarkdown.repair('plain words'), 'plain words');
    });
  });

  testWidgets('types a reply out, then settles on the whole thing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: StreamedMarkdown(reply, animate: true),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 120));
    final partial = renderedText(tester);
    expect(partial, contains('▍'), reason: 'no caret while typing');
    expect(partial.length, lessThan(reply.length));
    expect(partial, isNot(contains('**')), reason: 'flashed raw syntax');

    await tester.pumpAndSettle();
    final settled = renderedText(tester);
    expect(settled, isNot(contains('▍')));
    expect(settled, contains('Would you like me to create it?'));
  });

  testWidgets('a tap finishes the reveal early', (tester) async {
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: StreamedMarkdown(
                reply,
                animate: true,
                onDone: () => done = true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byType(StreamedMarkdown));
    await tester.pump();

    expect(done, isTrue);
    expect(renderedText(tester), contains('Would you like me to create it?'));
  });
}
