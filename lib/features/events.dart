import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/api_client.dart';
import '../core/design.dart';
import '../core/store.dart';
import '../core/time.dart';
import 'conflicts.dart';
import 'notes.dart';
import '../core/i18n.dart';

/// Opens a picker and returns the chosen file path, or null.
Future<String?> pickImagePath(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.white,
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
        color: const Color(0xffeee4ff).withValues(alpha: .65),
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
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.people_outline,
                          size: 16,
                          color: lilac,
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
                    const Icon(Icons.schedule, size: 15, color: muted),
                    const SizedBox(width: 8),
                    Text(
                      '${event.start.format(context)} – ${event.end.format(context)}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    if (event.completed) ...[
                      const Spacer(),
                      const Icon(
                        Icons.check_circle_outline,
                        size: 17,
                        color: purple,
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

  DateTime date = DateTime.now();
  TimeOfDay start = const TimeOfDay(hour: 9, minute: 0),
      end = const TimeOfDay(hour: 10, minute: 0);
  String reminder = 'None', repeat = 'Never';

  /// Newly uploaded poster id, or the existing one when unchanged.
  String? posterMediaId;
  String? posterUrl;
  bool posterCleared = false;

  /// For a repeating event, whether the pending save targets the whole series.
  bool seriesEdit = true;

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
    final initial = widget.initialStart;
    if (initial != null) {
      date = DateUtils.dateOnly(initial);
      start = TimeOfDay.fromDateTime(initial);
      end = TimeOfDay.fromDateTime(initial.add(const Duration(hours: 1)));
    }
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
  void _changeTime(VoidCallback change) {
    setState(change);
    _conflictDebounce?.cancel();
    setState(() => checkingConflicts = true);
    _conflictDebounce = Timer(
      const Duration(milliseconds: 350),
      _checkConflicts,
    );
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
      posterCleared = false;
    });
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
      backgroundColor: Colors.white,
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
              reminderMinutes: CalendarEvent.minutesForLabel(reminder),
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
              reminderMinutes: CalendarEvent.minutesForLabel(reminder),
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
              suffixIcon: Icon(icon, color: lilac, size: 20),
            ),
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: muted),
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
            InkWell(
              onTap: _choosePoster,
              child: Container(
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: lilac, width: .8),
                ),
                child: hasPoster
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: posterUrl != null
                                ? Image.network(posterUrl!, fit: BoxFit.cover)
                                : const Center(
                                    child: Text(
                                      'Poster ready to save',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                    ),
                                  ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: IconButton(
                              tooltip: tr('Remove poster'),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white70,
                              ),
                              onPressed: () => setState(() {
                                posterCleared = true;
                                posterMediaId = null;
                                posterUrl = null;
                              }),
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ),
                        ],
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            color: lilac,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'JPG, PNG or WEBP · tap to browse',
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            AppField(
              'Title',
              hint: 'Lunch with Ana',
              controller: title,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter an event title' : null,
            ),
            // No time zone picker: the calendar follows the phone's zone
            // automatically, so offering a field nobody could change only
            // invited doubt about which zone an event was saved in.
            picker(
              'Date',
              formatDay(date),
              Icons.calendar_month_outlined,
              () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2040),
                );
                if (picked != null) _changeTime(() => date = picked);
              },
            ),
            Row(
              children: [
                Expanded(
                  child: picker(
                    'Starts',
                    start.format(context),
                    Icons.schedule,
                    () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: start,
                      );
                      if (picked != null) _changeTime(() => start = picked);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: picker(
                    'End',
                    end.format(context),
                    Icons.schedule,
                    () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: end,
                      );
                      if (picked != null) _changeTime(() => end = picked);
                    },
                  ),
                ),
              ],
            ),
            ConflictPanel(
              checking: checkingConflicts,
              report: conflictReport,
              onPick: _applySlot,
            ),
            Row(
              children: [
                Expanded(
                  child: SelectField(
                    'Reminder',
                    value: reminder,
                    values: CalendarEvent.reminderOptions,
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
            AppField('Location', hint: 'Where is it?', controller: location),
            AppField(
              'Description',
              hint: 'Enter about your event...',
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
          backgroundColor: Colors.white,
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
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: Image.network(
                event.poster!.secureUrl,
                height: 170,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
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
            style: const TextStyle(color: muted, height: 1.45),
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
                  ? '${event.start.format(context)} – ${event.end.format(context)}'
                  : '${event.start.format(context)} → '
                        '${formatDay(event.occurrenceEndAt)}, '
                        '${event.end.format(context)}',
            ),
            (
              Icons.location_on_outlined,
              event.location.isEmpty ? 'No location added' : event.location,
            ),
            (Icons.alarm, event.reminder),
            (Icons.repeat, event.repeat),
          ].map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                children: [
                  Icon(row.$1, color: lilac, size: 23),
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
        color: const Color(0xffe2edff),
        child: Text(
          tr('Shared with you · {access}', {
            'access': tr(
              event.sharePermission == 'EDIT'
                  ? 'you can edit this event'
                  : 'view only',
            ),
          }),
          style: const TextStyle(fontSize: 12, color: muted),
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
              color: const Color(0xffe2edff),
              child: Text(
                tr('Your response: {status}', {
                  'status': tr(event.rsvpStatus!.toLowerCase()),
                }),
                style: const TextStyle(fontSize: 12, color: muted),
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
          Text(widget.event.title, style: const TextStyle(color: muted)),
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
                      ? const Color(0xffe2edff)
                      : const Color(0xfffff5f7),
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Icon(
                        permission == value
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: permission == value ? purple : muted,
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
                            style: const TextStyle(color: muted, fontSize: 10),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: chosen ? purple : const Color(0xffeee5fa),
              width: chosen ? 1.5 : .7,
            ),
          ),
          child: ListTile(
            leading: leading,
            title: Text(title, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: muted),
            ),
            trailing: chosen
                ? const Icon(Icons.check_circle, color: purple)
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
          const Padding(
            padding: EdgeInsets.only(bottom: 18),
            child: Text(
              'No notes for this event yet.',
              style: TextStyle(color: muted, fontSize: 13),
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
