import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/design.dart';
import '../core/store.dart';
import 'events.dart';

const _ink = Color(0xff1e1930);
const _soft = Color(0xff6f6688);
const _accent = Color(0xff7c3aed);

class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

/// The scrollable date strip runs three years from this origin. Indexing is
/// done in UTC so a daylight-saving shift can never move a day by one.
final _stripOrigin = DateTime.utc(DateTime.now().year - 1, 1, 1);
const _stripDays = 1096;
const _stripCell = 54.0;
const _stripGap = 6.0;
const _stripExtent = _stripCell + _stripGap;

class _CalendarTabState extends State<CalendarTab> {
  DateTime date = DateUtils.dateOnly(DateTime.now());
  DateTime now = DateTime.now();
  bool agenda = false;
  bool expanded = false;
  bool fetching = false;
  String? error;
  int request = 0;
  late final Timer clock;
  final strip = ScrollController();

  int _dayIndex(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day).difference(_stripOrigin).inDays;

  DateTime _dayAt(int index) {
    final day = _stripOrigin.add(Duration(days: index));
    return DateTime(day.year, day.month, day.day);
  }

  /// Brings the selected day into the middle of the strip after it changes
  /// from somewhere else — the arrows, "Today", or the date picker.
  void _centerStrip({bool animate = true}) {
    if (!strip.hasClients) return;
    final position = strip.position;
    final target =
        (_dayIndex(date) * _stripExtent) -
        (position.viewportDimension - _stripExtent) / 2;
    final offset = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (!animate || motion == Duration.zero) {
      strip.jumpTo(offset);
      return;
    }
    strip.animateTo(offset, duration: motion, curve: Curves.easeOutCubic);
  }

  Duration get motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 260);

  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
    // Open on today rather than at the start of the three-year range.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerStrip(animate: false);
    });
  }

  @override
  void dispose() {
    clock.cancel();
    strip.dispose();
    super.dispose();
  }

  Future<void> select(DateTime value, {bool refresh = false}) async {
    final token = ++request;
    setState(() {
      date = DateUtils.dateOnly(value);
      fetching = true;
      error = null;
    });
    _centerStrip();
    final store = StoreScope.read(context);
    try {
      if (refresh) {
        await store.loadEvents(anchor: date, silent: true);
      } else {
        await store.ensureWindow(date);
      }
    } catch (_) {
      if (mounted && token == request) {
        setState(() => error = 'Could not load events. Pull down to retry.');
      }
    } finally {
      if (mounted && token == request) setState(() => fetching = false);
    }
  }

  Future<void> create([int minute = 540]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EventForm(
          initialStart: DateTime(
            date.year,
            date.month,
            date.day,
            minute ~/ 60,
            minute % 60,
          ),
        ),
      ),
    );
    if (mounted) await select(date, refresh: true);
  }

  Future<void> open(CalendarEvent event) async {
    await go(context, '/event', event);
    if (mounted) await select(date, refresh: true);
  }

  List<CalendarEvent> eventsFor(AppStore store, DateTime day) {
    final end = DateTime(day.year, day.month, day.day + 1);
    return [...store.events, ...store.sharedEvents]
        .where(
          (event) =>
              event.occurrenceStartAt.isBefore(end) &&
              event.occurrenceEndAt.isAfter(day),
        )
        .toList()
      ..sort((a, b) => a.occurrenceStartAt.compareTo(b.occurrenceStartAt));
  }

  int minute(DateTime value) {
    if (value.isBefore(date)) return 0;
    if (!DateUtils.isSameDay(value, date)) return 1440;
    return value.hour * 60 + value.minute;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final events = eventsFor(store, date);
    return Backdrop(
      child: Stack(
        children: [
          RefreshIndicator(
            color: _accent,
            onRefresh: () => select(date, refresh: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: date,
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime(2200),
                                );
                                if (picked != null && mounted) {
                                  await select(picked);
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  DateFormat('MMMM yyyy').format(date),
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.5,
                                    color: _ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: _accent,
                              backgroundColor: const Color(0xffede9fe),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                            onPressed: () => select(DateTime.now()),
                            child: const Text('Today'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 78,
                        // Scrolls continuously across three years; the strip
                        // re-centres whenever the date is changed elsewhere.
                        child: ListView.builder(
                          controller: strip,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemExtent: _stripExtent,
                          itemCount: _stripDays,
                          itemBuilder: (context, index) {
                            final day = _dayAt(index);
                            final selected = DateUtils.isSameDay(day, date);
                            final today = DateUtils.isSameDay(day, now);
                            return Padding(
                              padding: const EdgeInsets.only(right: _stripGap),
                              child: Semantics(
                                selected: selected,
                                button: true,
                                label: DateFormat('EEEE, MMMM d').format(day),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => select(day),
                                  child: AnimatedContainer(
                                    duration: motion,
                                    curve: Curves.easeOutCubic,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? _accent
                                          : Colors.white.withValues(alpha: .65),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: today && !selected
                                            ? _accent
                                            : Colors.white.withValues(
                                                alpha: .7,
                                              ),
                                      ),
                                      boxShadow: selected
                                          ? [
                                              BoxShadow(
                                                color: _accent.withValues(
                                                  alpha: .2,
                                                ),
                                                blurRadius: 12,
                                                offset: const Offset(0, 5),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          DateFormat('E').format(day),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: selected
                                                ? Colors.white70
                                                : _soft,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          '${day.day}',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: selected
                                                ? Colors.white
                                                : _ink,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: eventsFor(store, day).isEmpty
                                                ? Colors.transparent
                                                : selected
                                                ? Colors.white
                                                : _accent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            tooltip: 'Previous week',
                            onPressed: () => select(
                              DateTime(date.year, date.month, date.day - 7),
                            ),
                            icon: const Icon(
                              Icons.chevron_left,
                              color: _soft,
                              size: 20,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              DateFormat('EEEE, MMM d').format(date),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _soft,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next week',
                            onPressed: () => select(
                              DateTime(date.year, date.month, date.day + 7),
                            ),
                            icon: const Icon(
                              Icons.chevron_right,
                              color: _soft,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .8),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: _accent.withValues(alpha: .12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final isAgenda in [false, true])
                                  Semantics(
                                    selected: agenda == isAgenda,
                                    button: true,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(25),
                                      onTap: () =>
                                          setState(() => agenda = isAgenda),
                                      child: AnimatedContainer(
                                        duration: motion,
                                        curve: Curves.easeOutCubic,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: agenda == isAgenda
                                              ? _accent
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            25,
                                          ),
                                        ),
                                        child: Text(
                                          isAgenda ? 'Agenda' : 'Day',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: agenda == isAgenda
                                                ? Colors.white
                                                : _soft,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (fetching || store.loadingEvents)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Text(
                              '${events.length} ${events.length == 1 ? 'event' : 'events'}',
                              style: const TextStyle(
                                color: _soft,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            error!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      AnimatedSwitcher(
                        duration: motion,
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, .025),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey('$date/$agenda/$expanded'),
                          child: agenda
                              ? buildAgenda(events)
                              : buildTimeline(events),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 24,
            bottom: 16,
            child: CreateEventButton(onPressed: create),
          ),
        ],
      ),
    );
  }

  Widget addPrompt(String label, int start) => Material(
    color: Colors.white.withValues(alpha: .45),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: () => create(start),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: _accent.withValues(alpha: .22)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.add, color: _accent, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget eventCard(CalendarEvent event, {bool compact = false}) {
    final color = event.isShared ? _accent : const Color(0xff22b3c4);
    return Semantics(
      button: true,
      label:
          '${event.title}, ${event.start.format(context)} to ${event.end.format(context)}',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => open(event),
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 5)),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 14,
              vertical: 10,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ink,
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w700,
                    decoration: event.completed
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${event.start.format(context)} – ${event.end.format(context)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _soft, fontSize: 11),
                ),
                if (!compact) ...[
                  const SizedBox(height: 8),
                  Text(
                    event.location.isNotEmpty
                        ? event.location
                        : event.isShared
                        ? 'Shared event'
                        : 'Personal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildAgenda(List<CalendarEvent> events) => Column(
    children: [
      if (events.isEmpty) ...[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Column(
            children: [
              Icon(Icons.wb_sunny_outlined, color: _accent, size: 36),
              SizedBox(height: 14),
              Text(
                'A little room to breathe',
                style: TextStyle(
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'No events scheduled for this day.',
                style: TextStyle(color: _soft),
              ),
            ],
          ),
        ),
      ],
      for (var i = 0; i < events.length; i++) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 62,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    events[i].occurrenceStartAt.isBefore(date)
                        ? 'Earlier'
                        : DateFormat(
                            'h:mm\na',
                          ).format(events[i].occurrenceStartAt),
                    style: const TextStyle(
                      color: _soft,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              Expanded(child: eventCard(events[i])),
            ],
          ),
        ),
        if (i + 1 < events.length &&
            minute(events[i + 1].occurrenceStartAt) >
                events
                    .take(i + 1)
                    .map((e) => minute(e.occurrenceEndAt))
                    .reduce(math.max))
          Padding(
            padding: const EdgeInsets.only(left: 62, bottom: 14),
            child: addPrompt(
              '${minute(events[i + 1].occurrenceStartAt) - events.take(i + 1).map((e) => minute(e.occurrenceEndAt)).reduce(math.max)} min free · tap to add',
              events
                  .take(i + 1)
                  .map((e) => minute(e.occurrenceEndAt))
                  .reduce(math.max),
            ),
          ),
      ],
      addPrompt('Add an event for this day', 540),
    ],
  );

  Widget buildTimeline(List<CalendarEvent> events) {
    final first = events.isEmpty
        ? 9
        : math.min(9, minute(events.first.occurrenceStartAt) ~/ 60);
    final startHour = expanded ? 0 : first;
    const hourHeight = 80.0;
    final scale = hourHeight / 60;
    final base = startHour * 60;
    final height = (24 - startHour) * hourHeight;
    // Place intersecting cards in separate lanes, including their minimum tap height.
    final placed =
        <
          ({
            CalendarEvent event,
            double top,
            double bottom,
            int lane,
            int columns,
          })
        >[];
    var group =
        <({CalendarEvent event, double top, double bottom, int lane})>[];
    final laneEnds = <double>[];
    void flush() {
      for (final item in group) {
        placed.add((
          event: item.event,
          top: item.top,
          bottom: item.bottom,
          lane: item.lane,
          columns: laneEnds.length,
        ));
      }
      group = [];
      laneEnds.clear();
    }

    for (final event in events) {
      final top = ((minute(event.occurrenceStartAt) - base) * scale).clamp(
        0.0,
        height - 64,
      );
      final bottom = math.min(
        height,
        math.max(top + 64, (minute(event.occurrenceEndAt) - base) * scale - 4),
      );
      if (laneEnds.isNotEmpty && laneEnds.every((end) => end <= top)) flush();
      var lane = laneEnds.indexWhere((end) => end <= top);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(bottom);
      } else {
        laneEnds[lane] = bottom;
      }
      group.add((event: event, top: top, bottom: bottom, lane: lane));
    }
    flush();
    final gaps = <({int start, int end})>[];
    var cursor = base;
    for (final event in events) {
      final begin = minute(event.occurrenceStartAt);
      if (begin - cursor >= 60) gaps.add((start: cursor, end: begin));
      cursor = math.max(cursor, minute(event.occurrenceEndAt));
    }
    if (1440 - cursor >= 60) gaps.add((start: cursor, end: 1440));
    final current = now.hour * 60 + now.minute;
    return Column(
      children: [
        if (first > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: _soft,
                backgroundColor: Colors.white.withValues(alpha: .5),
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () => setState(() => expanded = !expanded),
              icon: Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(
                expanded
                    ? 'Collapse quiet hours'
                    : '12–$first AM · nothing scheduled',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth - 58;
            return SizedBox(
              height: height + 16,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var hour = startHour; hour <= 24; hour++)
                    Positioned(
                      top: (hour - startHour) * hourHeight,
                      left: 0,
                      right: 0,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text(
                              '${hour % 12 == 0 ? 12 : hour % 12} ${hour < 12 || hour == 24 ? 'AM' : 'PM'}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _soft,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: _soft.withValues(alpha: .13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final gap in gaps)
                    Positioned(
                      top: (gap.start - base) * scale + 14,
                      left: 58,
                      right: 0,
                      child: addPrompt(
                        '${(gap.end - gap.start) ~/ 60}h free · tap to add',
                        gap.start,
                      ),
                    ),
                  for (final item in placed)
                    Positioned(
                      top: item.top + 4,
                      left: 58 + width * item.lane / item.columns,
                      width: width / item.columns - (item.columns > 1 ? 4 : 0),
                      height: item.bottom - item.top,
                      child: LayoutBuilder(
                        builder: (context, box) => ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: box.maxHeight,
                              ),
                              child: eventCard(
                                item.event,
                                compact:
                                    box.maxHeight < 110 || box.maxWidth < 160,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (DateUtils.isSameDay(date, now) && current >= base)
                    Positioned(
                      top: (current - base) * scale,
                      left: 52,
                      right: 0,
                      child: IgnorePointer(
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xffe11d48),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 2,
                                color: const Color(
                                  0xffe11d48,
                                ).withValues(alpha: .55),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xffe11d48),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                TimeOfDay.fromDateTime(now).format(context),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
