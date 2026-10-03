import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/api_client.dart';
import '../core/design.dart';
import '../core/store.dart';
import '../core/time.dart';
import 'conflicts.dart';
import 'notes.dart';
import 'past_time.dart';
import 'poster.dart';
import 'time_picker.dart';
import '../core/i18n.dart';

/// Opens a picker and returns the chosen file path, or null.
Future<String?> pickImagePath(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: lilac),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: lilac),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  try {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2000,
      imageQuality: 88,
    );
    return file?.path;
  } catch (error) {
    if (context.mounted) {
      toastError(
        context,
        tr('Could not open the picker: {error}', {'error': error}),
      );
    }
    return null;
  }
}

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, this.onChanged});
  final CalendarEvent event;

  /// Called after a mutation so the parent can refresh.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppPalette.of(
          context,
        ).wash(const Color(0xffeee4ff)).withValues(alpha: .65),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await go(context, '/event', event);
            onChanged?.call();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: TextStyle(
                          fontSize: 15,
                          decoration: event.completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (event.isShared)
                      Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.people_outline,
                          size: 16,
                          color: AppPalette.of(context).accent,
                        ),
                      )
                    else
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 19),
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await go(context, '/event/edit', event);
                            onChanged?.call();
                            return;
                          }
                          if (!context.mounted) return;
                          final confirmed = await confirm(
                            context,
                            'Delete event?',
                            'This event will be removed from your calendar.',
                            action: 'Delete',
                            danger: true,
                          );
                          if (!confirmed || !context.mounted) return;
                          final done = await runAction(
                            context,
                            () => store.deleteEvent(event),
                            success: 'Event deleted',
                          );
                          if (done) onChanged?.call();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                  ],
                ),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 15,
                      color: AppPalette.of(context).muted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${formatClock(event.start)} – ${formatClock(event.end)}',
                      style: TextStyle(
                        color: AppPalette.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                    if (event.completed) ...[
                      const Spacer(),
                      Icon(
                        Icons.check_circle_outline,
                        size: 17,
                        color: AppPalette.of(context).accent,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether an edit to a repeating event touches one occurrence or all of them.
enum _EditScope { occurrence, series }

class EventForm extends StatefulWidget {
  const EventForm({super.key, this.event, this.initialStart, this.groupId});
  final DateTime? initialStart;
  final CalendarEvent? event;

  /// Set when the form was opened from inside a group, so the new event is
  /// saved as a group event rather than a personal one (QA F05).
  final String? groupId;
  @override
  State<EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<EventForm> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      location = TextEditingController(),
      description = TextEditingController();

  // Set in initState: the time asked for, or the next full hour.
  late DateTime date;
  late TimeOfDay start, end;
  // A new event reminds by default. Left on 'None', an event people expected
  // to be reminded about simply passed in silence, which reads as push being
  // broken rather than as a field they never opened. Editing an existing event
  // still loads whatever it was saved with.
  String reminder = 'At event time', repeat = 'Never';

  /// Newly uploaded poster id, or the existing one when unchanged.
  String? posterMediaId;
  String? posterUrl;

  /// The picked file, previewed until the saved poster's URL comes back.
  String? posterPath;
  double? posterAspect;
  bool posterCleared = false;

  /// For a repeating event, whether the pending save targets the whole series.
  bool seriesEdit = true;

  /// Set when the user chose to record a time that has already passed, which
  /// is saved without reminders.
  bool savingPast = false;

  /// Live verdict on the time being picked, refreshed whenever it changes.
  ConflictReport? conflictReport;
  bool checkingConflicts = false;
  Timer? _conflictDebounce;
  int _conflictCheck = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkConflicts();
    });
    final initial = widget.initialStart ?? upcomingStart(DateTime.now());
    date = DateUtils.dateOnly(initial);
    start = TimeOfDay.fromDateTime(initial);
    end = TimeOfDay.fromDateTime(initial.add(const Duration(hours: 1)));
    final event = widget.event;
    if (event != null) {
      title.text = event.title;
      location.text = event.location;
      description.text = event.description;
      date = event.date;
      start = event.start;
      end = event.end;
      reminder = event.reminder;
      repeat = event.repeat;
      posterUrl = event.poster?.secureUrl;
      posterAspect = event.poster?.aspectRatio;
      posterMediaId = event.poster?.id;
    }
  }

  @override
  void dispose() {
    _conflictDebounce?.cancel();
    title.dispose();
    location.dispose();
    description.dispose();
    super.dispose();
  }

  /// The picked date and times as instants. An end at or before the start
  /// means the event runs past midnight into the next day.
  (DateTime, DateTime) _range() {
    final startsAt = combine(date, start);
    var endsAt = combine(date, end);
    if (!endsAt.isAfter(startsAt)) endsAt = endsAt.add(const Duration(days: 1));
    return (startsAt, endsAt);
  }

  /// Applies a date or time change and re-checks it once picking settles.
  ///
  /// Moving the start carries the end along so the event keeps its length,
  /// which is what moving an appointment normally means. The end may land on
  /// the next day; the duration line under the times says so. (Clamping it to
  /// 23:59 used to shorten late events, and comparing bare clock times reset
  /// the end of any overnight event whenever its date changed.)
  void _changeTime(VoidCallback change) {
    final (startsBefore, endsBefore) = _range();
    final length = endsBefore.difference(startsBefore);
    final startBefore = start, endBefore = end;
    setState(() {
      change();
      // A change that set the end itself (a suggested slot) keeps it.
      if (start != startBefore && end == endBefore) {
        end = TimeOfDay.fromDateTime(combine(date, start).add(length));
      }
    });
    _conflictDebounce?.cancel();
    setState(() => checkingConflicts = true);
    _conflictDebounce = Timer(
      const Duration(milliseconds: 350),
      _checkConflicts,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked != null && mounted) _changeTime(() => date = picked);
  }

  Future<void> _pickStart() async {
    final picked = await showClockPicker(
      context,
      title: tr('Start time'),
      date: date,
      initial: start,
    );
    if (picked != null && mounted) _changeTime(() => start = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showClockPicker(
      context,
      title: tr('End time'),
      date: date,
      initial: end,
      note: (time) => !combine(date, time).isAfter(combine(date, start))
          ? tr('Ends the next day')
          : null,
    );
    if (picked != null && mounted) _changeTime(() => end = picked);
  }

  void _applySlot(TimeSlot slot) => _changeTime(() {
    date = DateUtils.dateOnly(slot.startsAt);
    start = TimeOfDay.fromDateTime(slot.startsAt);
    end = TimeOfDay.fromDateTime(slot.endsAt);
  });

  /// Asks the server — which sees every event, repeating ones included — what
  /// the picked time runs into. Offline, the events already loaded stand in.
  Future<void> _checkConflicts() async {
    final store = StoreScope.read(context);
    if (store.calendarId.isEmpty) return;
    final check = ++_conflictCheck;
    final (startsAt, endsAt) = _range();
    setState(() => checkingConflicts = true);
    ConflictReport report;
    try {
      report = await store.api.events.checkConflicts(
        calendarId: store.calendarId,
        startsAt: startsAt,
        endsAt: endsAt,
        excludeEventId: widget.event?.id,
      );
    } catch (_) {
      report = ConflictReport(
        conflicts: [
          for (final other in store.events)
            if (other.id != widget.event?.id &&
                other.occurrenceStartAt.isBefore(endsAt) &&
                other.occurrenceEndAt.isAfter(startsAt))
              EventConflict(
                title: other.title,
                startsAt: other.occurrenceStartAt,
                endsAt: other.occurrenceEndAt,
              ),
        ],
      );
    }
    if (!mounted || check != _conflictCheck) return;
    setState(() {
      conflictReport = report;
      checkingConflicts = false;
    });
  }

  Future<void> _choosePoster() async {
    final path = await pickImagePath(context);
    if (path == null || !mounted) return;
    final store = StoreScope.of(context);
    final mediaId = await runTask(
      context,
      () => store.uploadEventPoster(path),
      success: 'Poster uploaded',
    );
    if (mediaId == null || !mounted) return;
    setState(() {
      posterMediaId = mediaId;
      posterUrl = null;
      posterAspect = null;
      posterPath = path;
      posterCleared = false;
    });
  }

  /// Whether this save would put the event's start in the past. A repeating
  /// series still has its future dates, and an edit that leaves an
  /// already-past event's time alone is not a new mistake.
  bool _startsInPast(DateTime startsAt) {
    if (!startsAt.isBefore(DateTime.now())) return false;
    final event = widget.event;
    final series = event == null || seriesEdit;
    if (series && repeat != 'Never') return false;
    return event == null || !startsAt.isAtSameMomentAs(event.occurrenceStartAt);
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final (startsAt, endsAt) = _range();

    // Editing a recurring event has to say whether it means this occurrence or
    // the whole series; the API has a separate endpoint for each.
    final event = widget.event;
    if (event != null && event.isRecurring) {
      final scope = await _askEditScope();
      if (scope == null || !mounted) return;
      seriesEdit = scope == _EditScope.series;
    }

    // A start that has already passed is nearly always the wrong day picked by
    // mistake — today instead of tomorrow. Ask before saving a missed
    // appointment, and never move the date on anyone's behalf.
    savingPast = false;
    if (_startsInPast(startsAt)) {
      final choice = await showPastTimeSheet(
        context,
        startsAt: startsAt,
        endsAt: endsAt,
      );
      if (choice == null || !mounted) return;
      if (choice == PastTimeChoice.change) {
        await _pickDate();
        return;
      }
      savingPast = true;
    }

    // Settle a clash before saving, instead of after the server refuses it.
    if (checkingConflicts || conflictReport == null) {
      _conflictDebounce?.cancel();
      await _checkConflicts();
      if (!mounted) return;
    }
    final report = conflictReport;
    if (report != null && !report.clear) {
      await _resolveClash(report, startsAt, endsAt);
      return;
    }
    await _submit(startsAt, endsAt, overrideConflicts: false);
  }

  /// Lets the user move to a suggested free time or keep both events.
  Future<void> _resolveClash(
    ConflictReport report,
    DateTime startsAt,
    DateTime endsAt,
  ) async {
    final decision = await showConflictSheet(
      context,
      report,
      title: title.text.trim(),
    );
    if (decision == null || !mounted) return;
    final slot = decision.slot;
    if (slot != null) {
      _applySlot(slot);
      await _submit(slot.startsAt, slot.endsAt, overrideConflicts: false);
    } else {
      await _submit(startsAt, endsAt, overrideConflicts: true);
    }
  }

  Future<_EditScope?> _askEditScope() => showDialog<_EditScope>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppPalette.of(dialogContext).surface,
      title: const Text('Repeating event'),
      content: const Text('Apply your changes to which events?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, _EditScope.occurrence),
          child: const Text('This event'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, _EditScope.series),
          child: const Text('All events'),
        ),
      ],
    ),
  );

  Future<void> _submit(
    DateTime startsAt,
    DateTime endsAt, {
    required bool overrideConflicts,
  }) async {
    final store = StoreScope.of(context);
    final event = widget.event;
    final result = await runTask<EventMutation>(
      context,
      () => event == null
          ? store.createEvent(
              title: title.text.trim(),
              startsAt: startsAt,
              endsAt: endsAt,
              description: description.text.trim(),
              location: location.text.trim(),
              posterMediaId: posterMediaId,
              recurrenceRrule: CalendarEvent.rruleForLabel(repeat),
              reminderMinutes: savingPast
                  ? const <int>[]
                  : CalendarEvent.minutesForLabel(reminder),
              overrideConflicts: overrideConflicts,
              groupId: widget.groupId,
            )
          : event.isRecurring && !seriesEdit
          ? store.updateOccurrence(
              event: event,
              title: title.text.trim(),
              startsAt: startsAt,
              endsAt: endsAt,
              description: description.text.trim(),
              location: location.text.trim(),
              overrideConflicts: overrideConflicts,
            )
          : store.updateEvent(
              event: event,
              title: title.text.trim(),
              startsAt: startsAt,
              endsAt: endsAt,
              description: description.text.trim(),
              location: location.text.trim(),
              posterMediaId: posterCleared ? null : posterMediaId,
              recurrenceRrule: CalendarEvent.rruleForLabel(repeat),
              reminderMinutes: savingPast
                  ? const <int>[]
                  : reminder == event.reminder
                  ? event.reminderMinutes
                  : CalendarEvent.minutesForLabel(reminder),
              overrideConflicts: overrideConflicts,
            ),
      success: event == null
          ? 'Event created'
          : event.isRecurring && !seriesEdit
          ? 'This event updated'
          : 'Event updated',
      onError: (error) => _onSaveError(error, startsAt, endsAt),
    );
    if (result != null && mounted) Navigator.pop(context, true);
  }

  /// The server refuses a clash the live check could not see coming (someone
  /// else booked the time meanwhile), and says what is free instead.
  void _onSaveError(ApiException error, DateTime startsAt, DateTime endsAt) {
    if (!error.isConflict) {
      toastError(context, error.message);
      return;
    }
    final details = error.details;
    final report = details is Map
        ? ConflictReport.fromJson(details.cast<String, dynamic>())
        : const ConflictReport();
    setState(() => conflictReport = report);
    _resolveClash(report, startsAt, endsAt);
  }

  Widget picker(
    String label,
    String value,
    IconData icon,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 10),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: InputDecorator(
            decoration: InputDecoration(
              suffixIcon: Icon(
                icon,
                color: AppPalette.of(context).accent,
                size: 20,
              ),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.of(context).muted,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final hasPoster =
        !posterCleared && (posterUrl != null || posterMediaId != null);
    return PageFrame(
      title: widget.event == null ? 'Create Event' : 'Edit Event',
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Flyer / Event Poster'),
            const SizedBox(height: 10),
            if (hasPoster && (posterUrl != null || posterPath != null)) ...[
              PosterImage(
                image: posterUrl != null
                    ? NetworkImage(posterUrl!)
                    : FileImage(File(posterPath!)) as ImageProvider,
                heroTag: posterUrl ?? posterPath!,
                aspectRatio: posterAspect,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      'Change image',
                      key: const ValueKey('poster-change'),
                      icon: Icons.photo_library_outlined,
                      outline: true,
                      onPressed: _choosePoster,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      'Remove',
                      key: const ValueKey('poster-remove'),
                      icon: Icons.delete_outline,
                      outline: true,
                      danger: true,
                      onPressed: () => setState(() {
                        posterCleared = true;
                        posterMediaId = null;
                        posterUrl = null;
                        posterPath = null;
                        posterAspect = null;
                      }),
                    ),
                  ),
                ],
              ),
            ] else
              InkWell(
                key: const ValueKey('poster-add'),
                onTap: _choosePoster,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 110,
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppPalette.of(context).accent,
                      width: .8,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: AppPalette.of(context).accent,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'JPG, PNG or WEBP · tap to browse',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppPalette.of(context).muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            AppField(
              'Title',
              hint: 'Add a title',
              controller: title,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter an event title' : null,
            ),
            // No time zone picker: the calendar follows the phone's zone
            // automatically, so offering a field nobody could change only
            // invited doubt about which zone an event was saved in.
            picker(
              'Date',
              formatWeekdayDay(date),
              Icons.calendar_month_outlined,
              _pickDate,
            ),
            _TimesCard(
              start: start,
              end: end,
              range: _range(),
              onStart: _pickStart,
              onEnd: _pickEnd,
            ),
            const SizedBox(height: 16),
            ConflictPanel(
              checking: checkingConflicts,
              report: conflictReport,
              onPick: _applySlot,
              onChangeTime: _pickStart,
            ),
            Row(
              children: [
                Expanded(
                  child: SelectField(
                    'Reminder',
                    value: reminder,
                    values: {
                      ...CalendarEvent.reminderOptions,
                      reminder,
                    }.toList(),
                    onChanged: (v) => setState(() => reminder = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectField(
                    'Repeat',
                    value: repeat,
                    values: CalendarEvent.repeatOptions,
                    onChanged: (v) => setState(() => repeat = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              reminder == 'None'
                  ? 'Reminders are off for this event.'
                  : 'Event-time notification is included. Choose an advance reminder for an extra notification before the event.',
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.of(context).muted,
              ),
            ),
            if (reminder != 'None' &&
                CalendarEvent.minutesForLabel(reminder).any(
                  (minutes) =>
                      minutes > 0 &&
                      !_range().$1
                          .subtract(Duration(minutes: minutes))
                          .isAfter(DateTime.now()),
                ))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'The advance reminder time has passed. You will still be notified when the event starts.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.of(context).muted,
                  ),
                ),
              ),
            AppField('Location', hint: 'Add a location', controller: location),
            AppField(
              'Description',
              hint: 'Add notes about your event...',
              controller: description,
              lines: 3,
            ),
            AsyncButton(
              widget.event == null ? 'Create Event' : 'Save Changes',
              onPressed: save,
            ),
          ],
        ),
      ),
    );
  }
}

class EventDetails extends StatefulWidget {
  const EventDetails({super.key, required this.event});
  final CalendarEvent event;
  @override
  State<EventDetails> createState() => _EventDetailsState();
}

class _EventDetailsState extends State<EventDetails> {
  late CalendarEvent event = widget.event;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// Refetches so permissions and the version counter are current before any
  /// mutation, which the API validates on every write.
  Future<void> _reload() async {
    final store = StoreScope.read(context);
    try {
      final fresh = await store.api.events.get(widget.event.id);
      // The endpoint returns the stored series, which carries no expanded
      // occurrence, so its occurrence fields collapse onto the series anchor.
      // Keep the occurrence this screen was opened for, or details and every
      // single-occurrence edit would silently act on the first date (QA F07).
      if (mounted) setState(() => event = _mergeOccurrence(fresh, store));
    } on ApiException catch (error) {
      if (mounted && !error.isNetworkError) toastError(context, error.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Restores the occurrence identity that `GET /events/:id` cannot carry.
  ///
  /// The recurrence slot this screen was opened for never changes, even when
  /// the occurrence is moved, so it is the reliable key: prefer the freshly
  /// expanded row the store holds for that slot, and fall back to the times
  /// already on screen when the store has not loaded that window.
  CalendarEvent _mergeOccurrence(CalendarEvent fresh, AppStore store) {
    if (!fresh.isRecurring) return fresh;
    final slot = event.occurrenceOriginalStartAt;
    final expanded = store.events.where(
      (item) =>
          item.id == fresh.id &&
          item.occurrenceOriginalStartAt.isAtSameMomentAs(slot),
    );
    final row = expanded.isEmpty ? null : expanded.first;
    return fresh.copyWith(
      occurrenceStartAt: row?.occurrenceStartAt ?? event.occurrenceStartAt,
      occurrenceEndAt: row?.occurrenceEndAt ?? event.occurrenceEndAt,
      occurrenceOriginalStartAt: slot,
    );
  }

  /// A repeating event can be cancelled for this date only, or ended entirely.
  Future<void> _delete() async {
    final store = StoreScope.read(context);

    if (event.isRecurring) {
      final scope = await showDialog<_EditScope>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppPalette.of(dialogContext).surface,
          title: const Text('Delete repeating event'),
          content: const Text('Remove which events?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _EditScope.occurrence),
              child: const Text('This event'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, _EditScope.series),
              child: const Text('All events'),
            ),
          ],
        ),
      );
      if (scope == null || !mounted) return;

      final done = await runAction(
        context,
        () => scope == _EditScope.occurrence
            ? store.cancelOccurrence(event)
            : store.deleteEvent(event),
        success: scope == _EditScope.occurrence
            ? 'This occurrence was removed'
            : 'Series deleted',
      );
      if (done && mounted) Navigator.pop(context);
      return;
    }

    final confirmed = await confirm(
      context,
      'Delete event?',
      'Remove this event from your calendar?',
      action: 'Delete',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final done = await runAction(
      context,
      () => store.deleteEvent(event),
      success: 'Event deleted',
    );
    if (done && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return PageFrame(
      title: 'Event Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (event.hasPoster)
            PosterImage(
              image: NetworkImage(event.poster!.secureUrl),
              heroTag: event.poster!.secureUrl,
              aspectRatio: event.poster!.aspectRatio,
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Description', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            event.description.isEmpty
                ? 'No description added.'
                : event.description,
            style: TextStyle(color: AppPalette.of(context).muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          ...[
            (Icons.calendar_month_outlined, formatDay(event.occurrenceStartAt)),
            (
              Icons.schedule,
              // An event running past midnight ends on a different date, and
              // showing "09:00 – 07:00" under one date reads as an error.
              // Name the end date when it differs (QA P03).
              DateUtils.isSameDay(
                    event.occurrenceStartAt,
                    event.occurrenceEndAt,
                  )
                  ? '${formatClock(event.start)} – ${formatClock(event.end)}'
                  : '${formatClock(event.start)} → '
                        '${formatDay(event.occurrenceEndAt)}, '
                        '${formatClock(event.end)}',
            ),
            (
              Icons.location_on_outlined,
              event.location.isEmpty ? 'No location added' : event.location,
            ),
            (Icons.alarm, event.reminderDescription),
            (Icons.repeat, event.repeat),
          ].map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                children: [
                  Icon(row.$1, color: AppPalette.of(context).accent, size: 23),
                  const SizedBox(width: 12),
                  Expanded(child: Text(row.$2)),
                ],
              ),
            ),
          ),
          _EventNotes(eventId: event.id),
          if (event.isShared)
            _invitationActions(store)
          else ...[
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    'Share Event',
                    outline: true,
                    icon: Icons.share_outlined,
                    onPressed: () => go(context, '/event/share', event),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    'Delete Event',
                    danger: true,
                    icon: Icons.delete_outline,
                    onPressed: event.canDelete ? _delete : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              'Edit Event',
              icon: Icons.edit_outlined,
              onPressed: event.canEdit
                  ? () async {
                      await go(context, '/event/edit', event);
                      await _reload();
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            Surface(
              padding: EdgeInsets.zero,
              child: CheckboxListTile(
                value: event.completed,
                onChanged: event.canEdit
                    ? (value) async {
                        final done = await runAction(
                          context,
                          () => store.setEventCompleted(event, value ?? false),
                          showSpinner: false,
                        );
                        if (done) await _reload();
                      }
                    : null,
                title: const Text(
                  'Mark as completed',
                  style: TextStyle(fontSize: 13),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _invitationActions(AppStore store) {
    Future<void> respond(String status) async {
      final done = await runAction(
        context,
        () => store.respondToInvitation(event, status),
        success: switch (status) {
          'ACCEPTED' => 'Invitation accepted',
          'DECLINED' => 'Invitation declined',
          _ => 'Marked as maybe',
        },
      );
      if (done && mounted) Navigator.pop(context);
    }

    if (!event.canRespond) {
      return Surface(
        color: AppPalette.of(context).wash(const Color(0xffe2edff)),
        child: Text(
          tr('Shared with you · {access}', {
            'access': tr(
              event.sharePermission == 'EDIT'
                  ? 'you can edit this event'
                  : 'view only',
            ),
          }),
          style: TextStyle(fontSize: 12, color: AppPalette.of(context).muted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (event.rsvpStatus != null && event.rsvpStatus != 'PENDING')
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Surface(
              color: AppPalette.of(context).wash(const Color(0xffe2edff)),
              child: Text(
                tr('Your response: {status}', {
                  'status': tr(event.rsvpStatus!.toLowerCase()),
                }),
                style: TextStyle(
                  fontSize: 12,
                  color: AppPalette.of(context).muted,
                ),
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                'Decline',
                outline: true,
                onPressed: () => respond('DECLINED'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(
                'Accept',
                onPressed: () => respond('ACCEPTED'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => respond('MAYBE'),
          child: const Text('Maybe'),
        ),
      ],
    );
  }
}

class ShareEventScreen extends StatefulWidget {
  const ShareEventScreen({super.key, required this.event});
  final CalendarEvent event;
  @override
  State<ShareEventScreen> createState() => _ShareEventScreenState();
}

class _ShareEventScreenState extends State<ShareEventScreen> {
  static const _permissions = {
    'View Only': 'VIEW_ONLY',
    'Confirm attendance': 'RESPOND',
    'Make changes': 'EDIT',
  };

  String permission = 'Confirm attendance';
  String query = '';
  bool groups = false;
  final selected = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.read(context).loadNetwork(silent: true);
    });
  }

  Future<void> _share() async {
    if (selected.isEmpty) {
      toast(context, 'Select at least one recipient.');
      return;
    }
    final store = StoreScope.of(context);
    final done = await runAction(
      context,
      () => store.shareEvent(
        event: widget.event,
        targetType: groups ? 'GROUP' : 'USER',
        targetIds: selected.toList(),
        permission: _permissions[permission]!,
      ),
      success: trCount(
        selected.length,
        'Event shared with {count} recipient',
        'Event shared with {count} recipients',
      ),
    );
    if (done && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final needle = query.toLowerCase();
    final people = store.contacts
        .where((person) => person.name.toLowerCase().contains(needle))
        .toList();
    final groupList = store.groups
        .where((group) => group.name.toLowerCase().contains(needle))
        .toList();

    return PageFrame(
      title: 'Share Event',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Share Event', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            widget.event.title,
            style: TextStyle(color: AppPalette.of(context).muted),
          ),
          const SizedBox(height: 26),
          const Text('Invited People Can', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 10),
          ..._permissions.keys.map(
            (value) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => permission = value),
                child: Surface(
                  color: permission == value
                      ? AppPalette.of(context).wash(const Color(0xffe2edff))
                      : AppPalette.of(context).wash(const Color(0xfffff5f7)),
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Icon(
                        permission == value
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: permission == value
                            ? AppPalette.of(context).accent
                            : AppPalette.of(context).muted,
                        size: 21,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(value),
                          Text(
                            value == 'View Only'
                                ? 'Can see event details but not respond'
                                : value == 'Make changes'
                                ? 'Can edit event details'
                                : 'Can accept, decline, or maybe',
                            style: TextStyle(
                              color: AppPalette.of(context).muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  'Select Contact',
                  outline: groups,
                  onPressed: () => setState(() {
                    groups = false;
                    selected.clear();
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  'Select Group',
                  outline: !groups,
                  onPressed: () => setState(() {
                    groups = true;
                    selected.clear();
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (value) => setState(() => query = value),
            decoration: InputDecoration(
              hintText: tr(groups ? 'Search groups' : 'Search contacts'),
              prefixIcon: const Icon(Icons.search, color: lilac),
            ),
          ),
          const SizedBox(height: 10),
          if (groups && groupList.isEmpty)
            const EmptyState(
              'You are not in any groups yet.',
              icon: Icons.groups_outlined,
            ),
          if (!groups && people.isEmpty)
            const EmptyState(
              'Add contacts before sharing an event.',
              icon: Icons.person_add_alt,
            ),
          ...(groups
              ? groupList.map(
                  (group) => _row(
                    id: group.id,
                    title: group.name,
                    subtitle: trCount(
                      group.memberCount,
                      '{count} member',
                      '{count} members',
                    ),
                    leading: const Icon(Icons.groups_outlined, color: lilac),
                  ),
                )
              : people.map(
                  (person) => _row(
                    id: person.id,
                    title: person.name,
                    subtitle: person.relation.isEmpty
                        ? person.email
                        : person.relation,
                    leading: Avatar(
                      index: person.avatarIndex,
                      name: person.name,
                      url: person.avatar?.secureUrl,
                    ),
                  ),
                )),
          const SizedBox(height: 10),
          AsyncButton('Share Event', onPressed: _share),
        ],
      ),
    );
  }

  Widget _row({
    required String id,
    required String title,
    required String subtitle,
    required Widget leading,
  }) {
    final chosen = selected.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () =>
            setState(() => chosen ? selected.remove(id) : selected.add(id)),
        child: Container(
          decoration: BoxDecoration(
            color: AppPalette.of(context).surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: chosen ? purple : AppPalette.of(context).border,
              width: chosen ? 1.5 : .7,
            ),
          ),
          child: ListTile(
            leading: leading,
            title: Text(title, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: AppPalette.of(context).muted,
              ),
            ),
            trailing: chosen
                ? Icon(Icons.check_circle, color: AppPalette.of(context).accent)
                : null,
          ),
        ),
      ),
    );
  }
}

/// Notes filed against one event, with a way to add another in place.
class _EventNotes extends StatefulWidget {
  const _EventNotes({required this.eventId});
  final String eventId;
  @override
  State<_EventNotes> createState() => _EventNotesState();
}

class _EventNotesState extends State<_EventNotes> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.read(context).loadNotes(silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notes = StoreScope.of(context).notesForEvent(widget.eventId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Notes', style: TextStyle(fontSize: 16)),
            ),
            TextButton.icon(
              onPressed: () async {
                await openNoteEditor(context, eventId: widget.eventId);
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
            VoiceNoteButton(
              eventId: widget.eventId,
              onSaved: () => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (notes.isEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 18),
            child: Text(
              'No notes for this event yet.',
              style: TextStyle(
                color: AppPalette.of(context).muted,
                fontSize: 13,
              ),
            ),
          )
        else
          ...notes.map(
            (note) => NoteTile(note: note, onChanged: () => setState(() {})),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// Start and end side by side with the length between them, so the whole
/// span reads at a glance before saving.
class _TimesCard extends StatelessWidget {
  const _TimesCard({
    required this.start,
    required this.end,
    required this.range,
    required this.onStart,
    required this.onEnd,
  });

  final TimeOfDay start, end;
  final (DateTime, DateTime) range;
  final VoidCallback onStart, onEnd;

  @override
  Widget build(BuildContext context) {
    final (startsAt, endsAt) = range;
    final overnight = !DateUtils.isSameDay(startsAt, endsAt);
    Widget row(String label, TimeOfDay time, VoidCallback onTap, Key key) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 15)),
              ),
              Material(
                color: AppPalette.of(context).wash(const Color(0xfff1ebff)),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: key,
                  borderRadius: BorderRadius.circular(12),
                  onTap: onTap,
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatClock(time),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down,
                          color: AppPalette.of(context).accent,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
    return Surface(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(tr('Starts'), start, onStart, const ValueKey('event-start')),
          Divider(height: 1, color: AppPalette.of(context).border),
          row(tr('Ends'), end, onEnd, const ValueKey('event-end')),
          Divider(height: 1, color: AppPalette.of(context).border),
          const SizedBox(height: 10),
          Text(
            [
              tr('Duration: {length}', {
                'length': formatDuration(endsAt.difference(startsAt)),
              }),
              if (overnight) tr('ends {day}', {'day': formatShortDay(endsAt)}),
            ].join(' · '),
            key: const ValueKey('event-duration'),
            style: TextStyle(fontSize: 13, color: AppPalette.of(context).muted),
          ),
        ],
      ),
    );
  }
}
