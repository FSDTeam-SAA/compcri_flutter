import 'dart:async';

import 'package:flutter/material.dart';

import 'design.dart';

/// Assistant replies arrive as Markdown, so the chat renders the slice of it a
/// model actually reaches for — headings, bullets, numbered steps, quotes,
/// fenced and inline code, bold, italics, links — rather than printing the
/// syntax. Syntax it doesn't know is left exactly as written, which keeps a
/// stray asterisk looking like a typo instead of a broken bubble.
class MarkdownText extends StatelessWidget {
  const MarkdownText(
    this.source, {
    super.key,
    this.style,
    this.accent = purple,
  });

  final String source;
  final TextStyle? style;
  final Color accent;

  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^(\s*)[-*+•]\s+(.*)$');
  static final _ordered = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
  static final _quote = RegExp(r'^\s*>\s?(.*)$');
  static final _rule = RegExp(r'^(?:[-*_]\s*){3,}$');

  /// One pass over every inline form. Code comes first so a backtick run wins
  /// over emphasis inside it; bold precedes italics so `**` is never read as a
  /// lone `*`.
  static final _inline = RegExp(
    r'`([^`]+)`'
    r'|\*\*(.+?)\*\*'
    r'|__(.+?)__'
    r'|~~(.+?)~~'
    r'|(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])'
    r'|(?<![\w_])_(?!\s)([^_\n]+?)(?<!\s)_(?![\w_])'
    r'|\[([^\]\n]*)\]\(([^)\s]+)\)',
  );

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _parse(source.trim(), base),
    );
  }

  List<Widget> _parse(String source, TextStyle base) {
    final out = <Widget>[];
    final paragraph = <String>[];

    void add(Widget block, double gap) => out.add(
      out.isEmpty
          ? block
          : Padding(
              padding: EdgeInsets.only(top: gap),
              child: block,
            ),
    );

    // Single newlines are kept as line breaks: a model laying a date and a
    // location on their own lines means them to stay on their own lines, even
    // though strict Markdown would reflow them into one paragraph.
    void flush() {
      if (paragraph.isEmpty) return;
      add(_text(paragraph.join('\n'), base), 10);
      paragraph.clear();
    }

    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // A fence runs to its closing pair, or to the end of the message while
      // one is still streaming in.
      if (trimmed.startsWith('```')) {
        flush();
        final body = <String>[];
        for (i++; i < lines.length; i++) {
          if (lines[i].trim().startsWith('```')) break;
          body.add(lines[i]);
        }
        add(_code(body.join('\n'), base), 12);
        continue;
      }

      if (trimmed.isEmpty) {
        flush();
        continue;
      }

      if (_rule.hasMatch(trimmed)) {
        flush();
        add(Container(height: 1, color: accent.withValues(alpha: .14)), 14);
        continue;
      }

      final heading = _heading.firstMatch(trimmed);
      if (heading != null) {
        flush();
        final bump = switch (heading[1]!.length) {
          1 => 4.0,
          2 => 2.5,
          _ => 1.0,
        };
        add(
          _text(
            heading[2]!,
            base.copyWith(
              fontSize: (base.fontSize ?? 13) + bump,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          14,
        );
        continue;
      }

      final quote = _quote.firstMatch(line);
      if (quote != null) {
        flush();
        add(_quoteBlock(quote[1]!, base), 12);
        continue;
      }

      final bullet = _bullet.firstMatch(line);
      if (bullet != null) {
        flush();
        add(_item('•', bullet[2]!, base, bullet[1]!.length), 6);
        continue;
      }

      final ordered = _ordered.firstMatch(line);
      if (ordered != null) {
        flush();
        add(_item('${ordered[2]}.', ordered[3]!, base, ordered[1]!.length), 6);
        continue;
      }

      paragraph.add(line);
    }
    flush();
    return out;
  }

  Widget _text(String raw, TextStyle style) =>
      Text.rich(TextSpan(style: style, children: _spans(raw, style)));

  /// List rows hang their text off the marker so a wrapped line stays aligned
  /// with the first one instead of sliding back under the dot.
  Widget _item(String marker, String content, TextStyle base, int indent) =>
      Padding(
        padding: EdgeInsets.only(left: (indent ~/ 2) * 14.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: marker.length > 2 ? 24 : 18,
              child: Text(
                marker,
                style: base.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  height: base.height ?? 1.45,
                ),
              ),
            ),
            Expanded(child: _text(content, base)),
          ],
        ),
      );

  Widget _quoteBlock(String content, TextStyle base) => Container(
    padding: const EdgeInsets.only(left: 11),
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: accent.withValues(alpha: .32), width: 3),
      ),
    ),
    child: _text(
      content,
      base.copyWith(color: muted, fontStyle: FontStyle.italic),
    ),
  );

  Widget _code(String body, TextStyle base) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xff151518).withValues(alpha: .045),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: accent.withValues(alpha: .12)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text(body, style: _mono(base)),
    ),
  );

  TextStyle _mono(TextStyle style) => style.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
    fontSize: (style.fontSize ?? 13) - 1,
    height: 1.45,
  );

  /// Emphasis nests by recursing on the match body, so `**Location:**` inside a
  /// sentence and a bold run holding inline code both survive.
  List<InlineSpan> _spans(String raw, TextStyle style) {
    final spans = <InlineSpan>[];
    var cursor = 0;

    TextSpan nested(String content, TextStyle nestedStyle) =>
        TextSpan(style: nestedStyle, children: _spans(content, nestedStyle));

    for (final match in _inline.allMatches(raw)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: raw.substring(cursor, match.start)));
      }
      cursor = match.end;

      final bold = match[2] ?? match[3];
      final italic = match[5] ?? match[6];
      if (match[1] != null) {
        spans.add(
          TextSpan(
            text: match[1],
            style: _mono(
              style,
            ).copyWith(backgroundColor: accent.withValues(alpha: .08)),
          ),
        );
      } else if (bold != null) {
        spans.add(nested(bold, style.copyWith(fontWeight: FontWeight.w700)));
      } else if (match[4] != null) {
        spans.add(
          nested(
            match[4]!,
            style.copyWith(
              decoration: TextDecoration.lineThrough,
              color: muted,
            ),
          ),
        );
      } else if (italic != null) {
        spans.add(nested(italic, style.copyWith(fontStyle: FontStyle.italic)));
      } else {
        final label = match[7]!.isEmpty ? match[8]! : match[7]!;
        spans.add(
          nested(
            label,
            style.copyWith(
              color: accent,
              decoration: TextDecoration.underline,
              decorationColor: accent.withValues(alpha: .4),
            ),
          ),
        );
      }
    }
    if (cursor < raw.length) {
      spans.add(TextSpan(text: raw.substring(cursor)));
    }
    return spans;
  }
}

/// A turn arrives from the API in one piece, so the bubble types it out itself
/// rather than dropping a wall of text at once. Every frame re-renders the
/// revealed slice through [MarkdownText] with its half-typed syntax repaired,
/// so a bold run or a bullet resolves as it lands instead of flashing its own
/// asterisks. Tapping the text finishes the reveal for readers who would
/// rather just have it.
class StreamedMarkdown extends StatefulWidget {
  const StreamedMarkdown(
    this.source, {
    super.key,
    this.style,
    this.accent = purple,
    this.animate = false,
    this.onDone,
    this.onTick,
  });

  final String source;
  final TextStyle? style;
  final Color accent;

  /// Only the reply that just landed types itself out; history renders whole.
  final bool animate;
  final VoidCallback? onDone;

  /// Fires a few times a second while typing so the list can stay pinned to
  /// the growing bubble.
  final VoidCallback? onTick;

  /// Syntax caught mid-keystroke would print itself, so a marker that is still
  /// being typed is dropped and any run left open is closed for this frame.
  static final _dangling = RegExp(r'(?:[*_~`]+|\[[^\]\n]*)$');

  static String repair(String partial) {
    final text = partial.replaceFirst(_dangling, '');
    if ('```'.allMatches(text).length.isOdd) return '$text\n```';
    return [
      text,
      if ('**'.allMatches(text).length.isOdd) '**',
      if ('~~'.allMatches(text).length.isOdd) '~~',
      if ('`'.allMatches(text).length.isOdd) '`',
    ].join();
  }

  @override
  State<StreamedMarkdown> createState() => _StreamedMarkdownState();
}

class _StreamedMarkdownState extends State<StreamedMarkdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(vsync: this);
  bool _started = false;
  int _frame = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
      _start();
      return;
    }
    _reveal.value = 1;
    // Reduced motion still owes the caller its completion, just without the
    // typing — and not during a build.
    if (widget.animate) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onDone?.call(),
      );
    }
  }

  /// A fixed per-character rate would leave a long answer crawling, so the
  /// pace is capped: a one-liner lands almost at once, the longest reply takes
  /// about three and a half seconds.
  void _start() {
    _reveal.duration = Duration(
      milliseconds: (widget.source.length * 14).clamp(350, 3500),
    );
    // The ticker future carries the completion rather than a status listener:
    // jumping the controller to 1 also reports `completed`, and that happens
    // mid-build here, where the caller can't be told anything. A cancelled
    // ticker never resolves, so a tap-to-finish reports itself instead.
    unawaited(
      _reveal.forward(from: 0).then((_) {
        if (mounted) widget.onDone?.call();
      }),
    );
  }

  @override
  void didUpdateWidget(StreamedMarkdown old) {
    super.didUpdateWidget(old);
    if (widget.source == old.source) return;
    if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
      _start();
    } else {
      _reveal.value = 1;
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  void _finish() {
    if (!_reveal.isAnimating) return;
    _reveal.stop();
    setState(() => _reveal.value = 1);
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    // The whole reply is the target, gaps between blocks included, so a reader
    // who wants it now doesn't have to land on a line of text.
    behavior: HitTestBehavior.opaque,
    onTap: _finish,
    child: AnimatedBuilder(
      animation: _reveal,
      builder: (context, _) {
        final typing = _reveal.value < 1;
        if (typing && widget.onTick != null && _frame++ % 4 == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onTick!());
        }
        final shown = (_reveal.value * widget.source.length).ceil();
        return MarkdownText(
          typing
              ? '${StreamedMarkdown.repair(widget.source.substring(0, shown))}▍'
              : widget.source,
          style: widget.style,
          accent: widget.accent,
        );
      },
    ),
  );
}
