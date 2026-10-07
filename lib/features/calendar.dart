import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:intl/intl.dart';

import '../core/design.dart';
import '../core/store.dart';
import '../core/time.dart';
import 'events.dart';
import '../core/i18n.dart';

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

/// The three ways the calendar can be read: one day hour by hour, the same day
/// as a list, or the whole month at a glance.
enum CalendarView {
  day('Day'),
  agenda('Agenda'),
  month('Month');

  const CalendarView(this.label);
  final String label;
}

class _CalendarTabState extends State<CalendarTab> with WidgetsBindingObserver {
  DateTime date = DateUtils.dateOnly(DateTime.now());
  DateTime now = DateTime.now();
  CalendarView view = CalendarView.day;
  bool expanded = false;
  bool fetching = false;
  String? error;

  /// The slot just tapped in the day view, outlined while its form is open.
  int? pendingSlot;
  int request = 0;
  late final Timer clock;
  final strip = ScrollController();
  bool get locked => isPastDay(date, now: now);
  bool get verified =>
      error == null &&
      !fetching &&
      !StoreScope.of(context).loadingEvents &&
      StoreScope.of(context).hasEventsFor(date);

  int _dayIndex(DateTime day) => DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(_stripOrigin).inDays;

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
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    clock.cancel();
    strip.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => now = DateTime.now());
    }
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
        setState(() => error = 'Could not load events.');
      }
    } finally {
      if (mounted && token == request) setState(() => fetching = false);
    }
  }

  /// Opens the form on [minute] of the selected day — or, with none given,
  /// at 9:00, or the next full hour when the day is today and 9:00 has gone.
  Future<void> create([int? minute]) async {
    if (isPastDay(date)) {
      toast(context, 'Past dates are view-only');
      return;
    }
    if (StoreScope.read(context).calendar?.canCreate != true) {
      toast(context, 'Creating events is not permitted');
      return;
    }
    final now = DateTime.now();
    final DateTime initial;
    if (minute != null) {
      initial = DateTime(date.year, date.month, date.day, 0, minute);
    } else {
      final nine = DateTime(date.year, date.month, date.day, 9);
      initial = DateUtils.isSameDay(date, now) && nine.isBefore(now)
          ? upcomingStart(now)
          : nine;
    }
    setState(() => pendingSlot = minute);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => EventForm(initialStart: initial)),
    );
    if (!mounted) return;
    setState(() => pendingSlot = null);
    await select(date, refresh: true);
  }

  Future<void> open(CalendarEvent event) async {
    await go(context, '/event', event);
    if (mounted) await select(date, refresh: true);
  }

  /// One tap of the arrows. The month grid moves a month at a time; the other
  /// views move a week, which is what the strip above them shows.
  ///
  /// Clamping the day keeps 31 January from landing on 2 March.
  DateTime _step(int direction) {
    if (view != CalendarView.month) {
      return DateTime(date.year, date.month, date.day + 7 * direction);
    }
    final month = DateTime(date.year, date.month + direction);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    return DateTime(month.year, month.month, date.day.clamp(1, days));
  }

  List<CalendarEvent> eventsFor(AppStore store, DateTime day) {
    final end = DateTime(day.year, day.month, day.day + 1);
    return store.visibleEvents
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
            color: AppPalette.of(context).accent,
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
                                  style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.5,
                                    color: AppPalette.of(context).ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: AppPalette.of(context).accent,
                              backgroundColor: AppPalette.of(
                                context,
                              ).wash(const Color(0xffede9fe)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                            onPressed: () => select(DateTime.now()),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Today'),
                                Text(
                                  formatShortDay(now),
                                  key: const ValueKey('calendar-today-date'),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
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
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? _accent
                                          : AppPalette.of(
                                              context,
                                            ).surface.withValues(alpha: .65),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: today && !selected
                                            ? _accent
                                            : AppPalette.of(context).border,
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
                                                : AppPalette.of(context).muted,
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
                                                : AppPalette.of(context).ink,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        if (isPastDay(day, now: now))
                                          Icon(
                                            Icons.lock_outline,
                                            size: 10,
                                            color: selected
                                                ? Colors.white70
                                                : AppPalette.of(context).muted,
                                          )
                                        else
                                          Container(
                                            width: 5,
                                            height: 5,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color:
                                                  eventsFor(store, day).isEmpty
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
                            tooltip: view == CalendarView.month
                                ? tr('Previous month')
                                : tr('Previous week'),
                            onPressed: () => select(_step(-1)),
                            icon: Icon(
                              Icons.chevron_left,
                              color: AppPalette.of(context).muted,
                              size: 20,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              // The month grid already names every day, so the
                              // line above it says which month you are in.
                              view == CalendarView.month
                                  ? DateFormat('MMMM yyyy').format(date)
                                  : DateFormat('EEEE, MMM d').format(date),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppPalette.of(context).muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: view == CalendarView.month
                                ? tr('Next month')
                                : tr('Next week'),
                            onPressed: () => select(_step(1)),
                            icon: Icon(
                              Icons.chevron_right,
                              color: AppPalette.of(context).muted,
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
                              color: AppPalette.of(
                                context,
                              ).surface.withValues(alpha: .8),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: _accent.withValues(alpha: .12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final option in CalendarView.values)
                                  Semantics(
                                    selected: view == option,
                                    button: true,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(25),
                                      onTap: () =>
                                          setState(() => view = option),
                                      child: AnimatedContainer(
                                        duration: motion,
                                        curve: Curves.easeOutCubic,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: view == option
                                              ? _accent
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            25,
                                          ),
                                        ),
                                        child: Text(
                                          option.label,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: view == option
                                                ? Colors.white
                                                : AppPalette.of(context).muted,
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
                              trCount(
                                events.length,
                                '{count} event',
                                '{count} events',
                              ),
                              style: TextStyle(
                                color: AppPalette.of(context).muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      if (locked) ...[
                        Surface(
                          child: Row(
                            children: [
                              Icon(
                                Icons.lock_outline,
                                color: AppPalette.of(context).accent,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Past dates are view-only',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      'You can view past dates, but can’t add or move events.',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // A failed load — here or at launch — leaves the day
                      // unknown: say so and offer a retry.
                      if (error != null ||
                          (!fetching &&
                              !store.loadingEvents &&
                              !store.hasEventsFor(date)))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Surface(
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.cloud_off_rounded,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    tr(
                                      '{error} Free time can’t be shown until they load.',
                                      {
                                        'error': tr(
                                          error ?? 'Could not load events.',
                                        ),
                                      },
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                TextButton(
                                  key: const ValueKey('calendar-retry'),
                                  onPressed: () => select(date, refresh: true),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
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
                          key: ValueKey('$date/${view.name}/$expanded'),
                          child: switch (view) {
                            CalendarView.agenda => buildAgenda(events),
                            CalendarView.month => buildMonth(store),
                            CalendarView.day => buildTimeline(events),
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (store.calendar?.canCreate == true && !locked)
            Positioned(
              right: 24,
              bottom: 16,
              child: CreateEventButton(onPressed: create),
            ),
        ],
      ),
    );
  }

  /// The outline of the event about to be created on a tapped slot.
  Widget newEventSlot(int minute) {
    final startsAt = DateTime(date.year, date.month, date.day, 0, minute);
    final accent = AppPalette.of(context).accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: .6), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(Icons.add_circle, color: accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'New event',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            formatClockRange(startsAt, startsAt.add(const Duration(hours: 1))),
            style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget addPrompt(String label, int start) => Material(
    color: AppPalette.of(context).surface.withValues(alpha: .45),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: locked || StoreScope.of(context).calendar?.canCreate != true
          ? null
          : () => create(start),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: _accent.withValues(alpha: .22)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              locked ? Icons.lock_outline : Icons.add,
              color: AppPalette.of(context).accent,
              size: 17,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                locked ? 'Past date — adding disabled' : label,
                style: TextStyle(
                  color: AppPalette.of(context).accent,
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
      label: tr('{title}, {start} to {end}', {
        'title': event.title,
        'start': formatClock(event.start),
        'end': formatClock(event.end),
      }),
      child: Material(
        color: AppPalette.of(context).surface,
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
                    color: AppPalette.of(context).ink,
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w700,
                    decoration: event.completed
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatClock(event.start)} – ${formatClock(event.end)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppPalette.of(context).muted,
                    fontSize: 11,
                  ),
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

  /// The whole month at a glance: which days carry something, and how the
  /// selected one sits among them. The selected day’s list stays below the
  /// grid, and switching views preserves the same date.
  Widget buildMonth(AppStore store) {
    final first = DateTime(date.year, date.month);
    final daysInMonth = DateUtils.getDaysInMonth(date.year, date.month);
    // Monday-first, matching the week strip above.
    final leading = (first.weekday + 6) % 7;
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var day = 1; day <= daysInMonth; day++)
        DateTime(date.year, date.month, day),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  DateFormat('E').format(DateTime(2024, 1, 1 + i)),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.of(context).muted,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cells.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: .82,
          ),
          itemBuilder: (context, index) {
            final day = cells[index];
            if (day == null) return const SizedBox.shrink();
            final count = eventsFor(store, day).length;
            final selected = DateUtils.isSameDay(day, date);
            final today = DateUtils.isSameDay(day, now);
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => select(day),
              child: Container(
                decoration: BoxDecoration(
                  color: selected
                      ? _accent
                      : AppPalette.of(context).surface.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: today && !selected
                        ? _accent
                        : _accent.withValues(alpha: .1),
                    width: today && !selected ? 1.4 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white
                            : AppPalette.of(context).ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // A row of dots reads as "how busy" without needing a
                    // number; past three they stop being countable anyway.
                    SizedBox(
                      height: 5,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < count.clamp(0, 3); i++)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected
                                    ? Colors.white
                                    : AppPalette.of(context).accent,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        Text(
          formatWeekdayDay(date),
          key: const ValueKey('month-selected-date'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        buildAgenda(eventsFor(store, date)),
      ],
    );
  }

  Widget buildAgenda(List<CalendarEvent> events) => Column(
    children: [
      if (events.isEmpty && verified) ...[
        Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Column(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                color: AppPalette.of(context).accent,
                size: 36,
              ),
              SizedBox(height: 14),
              Text(
                'A little room to breathe',
                style: TextStyle(
                  color: AppPalette.of(context).ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'No events scheduled for this day.',
                style: TextStyle(color: AppPalette.of(context).muted),
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
                        : formatClockAt(
                            events[i].occurrenceStartAt,
                          ).replaceFirst(' ', '\n'),
                    style: TextStyle(
                      color: AppPalette.of(context).muted,
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
        if (verified &&
            !locked &&
            StoreScope.of(context).calendar?.canCreate == true &&
            i + 1 < events.length &&
            minute(events[i + 1].occurrenceStartAt) >
                events
                    .take(i + 1)
                    .map((e) => minute(e.occurrenceEndAt))
                    .reduce(math.max))
          Padding(
            padding: const EdgeInsets.only(left: 62, bottom: 14),
            child: addPrompt(
              tr('{minutes} min free · tap to add', {
                'minutes':
                    minute(events[i + 1].occurrenceStartAt) -
                    events
                        .take(i + 1)
                        .map((e) => minute(e.occurrenceEndAt))
                        .reduce(math.max),
              }),
              events
                  .take(i + 1)
                  .map((e) => minute(e.occurrenceEndAt))
                  .reduce(math.max),
            ),
          ),
      ],
      if (locked || StoreScope.of(context).calendar?.canCreate == true)
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
    // Free time is only claimed for a day whose events really loaded; after a
    // failed fetch an empty day is unknown, not free.
    final current = now.hour * 60 + now.minute;
    final pending = pendingSlot;
    return Column(
      children: [
        if (first > 0 && verified)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppPalette.of(context).muted,
                backgroundColor: AppPalette.of(
                  context,
                ).surface.withValues(alpha: .5),
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
                    : tr('12–{first} AM · nothing scheduled', {'first': first}),
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
                              formatHour(hour),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppPalette.of(context).muted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: AppPalette.of(
                                context,
                              ).muted.withValues(alpha: .13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Tapping empty time opens the form on that slot. A drag is a
                  // scroll, not a tap, so scrolling never starts an event, and
                  // event cards above this layer still open their details.
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 58,
                    right: 0,
                    child: GestureDetector(
                      key: const ValueKey('timeline-slots'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp:
                          locked ||
                              StoreScope.of(context).calendar?.canCreate != true
                          ? null
                          : (details) {
                              final tapped =
                                  base + details.localPosition.dy / scale;
                              final slot = (tapped ~/ 30) * 30;
                              if (slot >= 0 && slot < 1440) create(slot);
                            },
                    ),
                  ),
                  if (pending != null && pending >= base)
                    Positioned(
                      top: (pending - base) * scale + 4,
                      left: 58,
                      right: 0,
                      height: hourHeight - 8,
                      child: IgnorePointer(child: newEventSlot(pending)),
                    ),
                  for (final gap
                      in verified &&
                              !locked &&
                              StoreScope.of(context).calendar?.canCreate == true
                          ? gaps
                          : const <({int start, int end})>[])
                    Positioned(
                      top: (gap.start - base) * scale + 14,
                      left: 58,
                      right: 0,
                      child: addPrompt(
                        tr('{hours}h free · tap to add', {
                          'hours': (gap.end - gap.start) ~/ 60,
                        }),
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
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.error,
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
                                color: Theme.of(context).colorScheme.error,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                formatClockAt(now),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onError,
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
